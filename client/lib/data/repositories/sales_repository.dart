import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import '../local/models.dart';

class InsufficientStockException implements Exception {
  final String productoId;
  final double disponible;
  final double solicitado;
  InsufficientStockException(this.productoId, this.disponible, this.solicitado);

  @override
  String toString() => 'Stock insuficiente para $productoId: Disp: $disponible, Req: $solicitado';
}

/// Modelo de datos para el historial de ventas
class SaleRecord {
  final String id;
  final String folioTicket;
  final double total;
  final DateTime fechaVenta;
  final String estatus;
  final List<dynamic> pagosDesglose;

  SaleRecord({
    required this.id,
    required this.folioTicket,
    required this.total,
    required this.fechaVenta,
    required this.estatus,
    required this.pagosDesglose,
  });

  factory SaleRecord.fromMap(Map<String, dynamic> map) {
    return SaleRecord(
      id: map['id'] as String,
      folioTicket: map['folio_ticket'] as String? ?? 'S/F',
      total: (map['total'] as num).toDouble(),
      fechaVenta: DateTime.parse(map['fecha_venta'] as String),
      estatus: map['estatus'] as String? ?? 'completado',
      pagosDesglose: jsonDecode(map['pagos_desglose'] as String? ?? '[]'),
    );
  }
}

class SalesRepository {
  final DatabaseHelper _dbHelper;

  SalesRepository({DatabaseHelper? dbHelper}) 
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  // ===========================================================================
  // 1. TRANSACCIÓN ATÓMICA DE VENTA (ACID + BOM LIGERO + OUTBOX PATTERN)
  // ===========================================================================
  
  Future<void> processSaleTransaction(SaleTransactionRequest sale) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      final isoNow = sale.fechaVenta.toIso8601String();

      // 1. Inserción de Encabezado en 'ventas'
      await txn.insert(
        'ventas',
        {
          'id': sale.ventaId,
          'corte_caja_id': sale.corteCajaId,
          'folio_ticket': sale.folioTicket,
          'subtotal': sale.subtotal,
          'descuento_total': sale.descuentoTotal,
          'impuestos_total': sale.impuestosTotal,
          'total': sale.total,
          'pagos_desglose': jsonEncode(sale.pagosDesglose.map((p) => p.toJson()).toList()),
          'fecha_venta': isoNow,
          'estatus': 'completado'
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final List<Map<String, dynamic>> insumosDescontadosLog = [];

      // 2. Inserción de cada Partida y Reducción de Stock Decimal / Insumo Vinculado
      for (final item in sale.items) {
        await txn.insert(
          'detalles_venta',
          item.toMap(sale.ventaId),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        // Si es el artículo común, no afecta inventario físico
        if (item.productoId == 'ART-COMUN') {
          continue;
        }

        // Consultar atributos del producto en base de datos
        final prodRows = await txn.query(
          'productos',
          columns: ['id', 'es_servicio', 'insumo_vinculado_id', 'cantidad_insumo', 'nombre', 'stock_actual', 'departamento'],
          where: 'id = ?',
          whereArgs: [item.productoId],
          limit: 1,
        );

        if (prodRows.isNotEmpty) {
          final prod = prodRows.first;
          final bool esServicio = (prod['es_servicio'] as int? ?? 0) == 1;
          final String? insumoId = prod['insumo_vinculado_id'] as String?;
          final double cantInsumo = (prod['cantidad_insumo'] as num?)?.toDouble() ?? 1.0;
          final String prodNombre = (prod['nombre'] as String?) ?? item.nombre;
          final String? depto = prod['departamento'] as String?;

          if (esServicio && insumoId != null && insumoId.trim().isNotEmpty) {
            // REGLA DE NEGOCIO: Es un servicio con insumo vinculado.
            // Se descuenta automáticamente el stock del insumo físico vinculado.
            final double cantidadADescontar = item.cantidad * cantInsumo;

            final insumoRows = await txn.query(
              'productos',
              columns: ['id', 'nombre', 'stock_actual', 'departamento'],
              where: 'id = ?',
              whereArgs: [insumoId],
              limit: 1,
            );
            final double currentInsumoStock = insumoRows.isNotEmpty ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0) : 0.0;
            final String insumoNombre = insumoRows.isNotEmpty ? (insumoRows.first['nombre'] as String? ?? insumoId) : insumoId;
            final String? insumoDepto = insumoRows.isNotEmpty ? insumoRows.first['departamento'] as String? : null;
            final double newInsumoStock = currentInsumoStock - cantidadADescontar;

            final updatedRows = await txn.rawUpdate('''
              UPDATE productos 
              SET stock_actual = stock_actual - ?, 
                  updated_at = ? 
              WHERE id = ?
            ''', [cantidadADescontar, isoNow, insumoId]);

            if (updatedRows == 0) {
              throw Exception('Insumo vinculado $insumoId no encontrado para el servicio ${item.productoId}');
            }

            await _dbHelper.logInventoryMovement(
              db: txn,
              productoId: insumoId,
              productoDesc: insumoNombre,
              tipo: 'VENTA_SERVICIO',
              cantidad: cantidadADescontar,
              stockAnterior: currentInsumoStock,
              stockNuevo: newInsumoStock,
              usuarioId: 'cajero',
              departamento: insumoDepto,
              motivo: 'Consumo por servicio: $prodNombre (Folio ${sale.folioTicket ?? sale.ventaId})',
            );

            insumosDescontadosLog.add({
              'servicio_id': item.productoId,
              'insumo_id': insumoId,
              'cantidad_servicio': item.cantidad,
              'cantidad_insumo_descontada': cantidadADescontar,
            });
          } else if (!esServicio) {
            // Producto físico normal: descuenta su propio stock
            final double currentStock = (prod['stock_actual'] as num?)?.toDouble() ?? 0.0;
            final double newStock = currentStock - item.cantidad;

            final updatedRows = await txn.rawUpdate('''
              UPDATE productos 
              SET stock_actual = stock_actual - ?, 
                  updated_at = ? 
              WHERE id = ?
            ''', [item.cantidad, isoNow, item.productoId]);

            if (updatedRows == 0) {
              throw Exception('No se encontró el producto ${item.productoId} para descontar stock.');
            }

            await _dbHelper.logInventoryMovement(
              db: txn,
              productoId: item.productoId,
              productoDesc: prodNombre,
              tipo: 'VENTA',
              cantidad: item.cantidad,
              stockAnterior: currentStock,
              stockNuevo: newStock,
              usuarioId: 'cajero',
              departamento: depto,
              motivo: 'Venta Folio ${sale.folioTicket ?? sale.ventaId}',
            );
          }
          // Si es servicio puro sin insumo vinculado (insumoId == null), no modifica inventario.
        } else {
          // Si no se encuentra en el catálogo local pero tiene ID (fallback)
          await txn.rawUpdate('''
            UPDATE productos 
            SET stock_actual = stock_actual - ?, 
                updated_at = ? 
            WHERE id = ?
          ''', [item.cantidad, isoNow, item.productoId]);
        }
      }

      // 3. Empaquetado del Evento Outbox con desglose de insumos consumidos
      final outboxPayload = jsonEncode({
        'venta_id': sale.ventaId,
        'corte_caja_id': sale.corteCajaId,
        'folio_ticket': sale.folioTicket,
        'totales': {
          'subtotal': sale.subtotal,
          'descuentos': sale.descuentoTotal,
          'impuestos': sale.impuestosTotal,
          'total': sale.total,
        },
        'pagos': sale.pagosDesglose.map((p) => p.toJson()).toList(),
        'items': sale.items.map((i) => i.toJson()).toList(),
        'insumos_consumidos': insumosDescontadosLog,
        'timestamp': isoNow,
      });

      // 4. Inserción en 'sync_queue'
      await txn.insert(
        'sync_queue',
        {
          'id': sale.ventaId, 
          'event_type': 'VENTA_REGISTRADA',
          'payload': outboxPayload,
          'sync_status': 'pending',
          'retry_count': 0,
          'error_code': null,
          'created_at': isoNow,
          'synced_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  // ===========================================================================
  // 2. MOTOR DE BÚSQUEDA INTELIGENTE, COMODÍN % Y VARIANTES / EQUIVALENCIAS
  // ===========================================================================

  Future<Product?> findProductByBarcodeOrSku(String code) async {
    final db = await _dbHelper.database;
    final cleanCode = code.trim();

    final results = await db.query(
      'productos',
      where: 'codigo_barras = ? OR sku = ?',
      whereArgs: [cleanCode, cleanCode],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return Product.fromMap(results.first);
    }
    return null;
  }

  /// Búsqueda inteligente con soporte de comodín '%' y agrupación por moldes/equivalencias
  Future<List<Product>> searchProductsAdvanced(String query, {int limit = 35}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final db = await _dbHelper.database;
    final bool isDeepSearch = cleanQuery.startsWith('%');
    final String searchTerm = isDeepSearch ? cleanQuery.substring(1).trim() : cleanQuery;
    
    if (searchTerm.isEmpty) return [];

    List<Map<String, dynamic>> directRows = [];

    if (isDeepSearch) {
      // Búsqueda profunda: busca además dentro de descripcion técnica, compatibilidad, etc.
      final pattern = '%$searchTerm%';
      directRows = await db.rawQuery('''
        SELECT * FROM productos
        WHERE descripcion LIKE ? 
           OR nombre LIKE ? 
           OR sku LIKE ? 
           OR marca LIKE ? 
           OR codigo_barras LIKE ?
        LIMIT ?
      ''', [pattern, pattern, pattern, pattern, pattern, limit]);
    } else {
      // Búsqueda estándar (sin %): busca en codigo_barras, sku, nombre y marca
      final pattern = '%$searchTerm%';
      directRows = await db.rawQuery('''
        SELECT * FROM productos
        WHERE codigo_barras = ? 
           OR sku = ? 
           OR sku LIKE ? 
           OR nombre LIKE ? 
           OR marca LIKE ?
        LIMIT ?
      ''', [searchTerm, searchTerm, pattern, pattern, pattern, limit]);
    }

    final List<Product> directProducts = directRows.map((r) => Product.fromMap(r)).toList();
    final Set<String> directIds = directProducts.map((p) => p.id).toSet();

    // Identificar códigos de equivalencia (Universal Cross-Reference)
    final Set<String> equivalencias = directProducts
        .map((p) => p.codigoEquivalencia)
        .where((eq) => eq != null && eq.trim().isNotEmpty)
        .cast<String>()
        .toSet();

    final List<Product> equivalentVariants = [];
    if (equivalencias.isNotEmpty) {
      final placeholders = List.filled(equivalencias.length, '?').join(', ');
      final variantRows = await db.rawQuery('''
        SELECT * FROM productos
        WHERE codigo_equivalencia IN ($placeholders)
      ''', equivalencias.toList());

      for (final r in variantRows) {
        final prod = Product.fromMap(r);
        if (!directIds.contains(prod.id)) {
          equivalentVariants.add(prod);
          directIds.add(prod.id);
        }
      }
    }

    final List<Product> allResults = [...directProducts, ...equivalentVariants];

    // Ordenamiento estricto: Coincidencia más directa primero, y justo debajo sus variantes equivalentes
    allResults.sort((a, b) {
      final scoreA = _calculateRelevanceScore(a, searchTerm);
      final scoreB = _calculateRelevanceScore(b, searchTerm);
      if (scoreA != scoreB) {
        return scoreA.compareTo(scoreB);
      }
      final marcaA = a.marca ?? '';
      final marcaB = b.marca ?? '';
      final cmpMarca = marcaA.compareTo(marcaB);
      if (cmpMarca != 0) return cmpMarca;
      return a.nombre.compareTo(b.nombre);
    });

    if (allResults.length > limit) {
      return allResults.sublist(0, limit);
    }
    return allResults;
  }

  int _calculateRelevanceScore(Product p, String term) {
    final lowerTerm = term.toLowerCase();
    final sku = (p.sku ?? '').toLowerCase();
    final barcode = (p.codigoBarras ?? '').toLowerCase();
    final nombre = p.nombre.toLowerCase();

    if (sku == lowerTerm || barcode == lowerTerm) return 1;
    if (nombre == lowerTerm) return 2;
    if (sku.startsWith(lowerTerm)) return 3;
    if (nombre.startsWith(lowerTerm)) return 4;
    if (sku.contains(lowerTerm)) return 5;
    if (nombre.contains(lowerTerm)) return 6;
    if ((p.marca ?? '').toLowerCase().contains(lowerTerm)) return 7;
    if (p.descripcion.toLowerCase().contains(lowerTerm)) return 8;
    return 9; // Variante por equivalencia de molde universal
  }

  // Compatibilidad con invocaciones legacy
  Future<List<Product>> searchProductsByDescription(String query, {int limit = 15}) async {
    return searchProductsAdvanced(query, limit: limit);
  }

  // ===========================================================================
  // 3. HISTORIAL Y DEVOLUCIONES (CAJ-07 CON REVERSIÓN DE INSUMOS)
  // ===========================================================================

  Future<List<SaleRecord>> getSalesHistory({String query = '', int limit = 50}) async {
    final db = await _dbHelper.database;
    final cleanQuery = query.trim();
    
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (cleanQuery.isNotEmpty) {
      whereClause = 'folio_ticket LIKE ? OR id = ?';
      whereArgs = ['%$cleanQuery%', cleanQuery];
    }

    final results = await db.query(
      'ventas',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereClause.isEmpty ? null : whereArgs,
      orderBy: 'fecha_venta DESC',
      limit: limit,
    );

    return results.map((r) => SaleRecord.fromMap(r)).toList();
  }

  Future<List<SaleDetailItem>> getSaleDetails(String ventaId) async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT d.*, p.nombre, p.descripcion, p.ubicacion, p.sku, p.marca, p.es_servicio, p.insumo_vinculado_id, p.cantidad_insumo
      FROM detalles_venta d
      LEFT JOIN productos p ON d.producto_id = p.id
      WHERE d.venta_id = ?
    ''', [ventaId]);

    return results.map((map) {
      final String desc = (map['descripcion'] as String?) ?? 'Producto ${map['producto_id']}';
      final String nom = (map['nombre'] as String?) ?? desc;
      return SaleDetailItem(
        id: map['id'] as String,
        productoId: map['producto_id'] as String,
        nombre: nom,
        descripcion: desc,
        cantidad: (map['cantidad'] as num).toDouble(),
        precioHistorico: (map['precio_historico'] as num).toDouble(),
        totalLinea: (map['total_linea'] as num).toDouble(),
        costoHistorico: (map['costo_historico'] as num?)?.toDouble() ?? 0.0,
        descuentoLinea: (map['descuento_linea'] as num?)?.toDouble() ?? 0.0,
        ubicacion: map['ubicacion'] as String?,
        sku: map['sku'] as String?,
        marca: map['marca'] as String?,
        esServicio: (map['es_servicio'] as int? ?? 0) == 1,
        insumoVinculadoId: map['insumo_vinculado_id'] as String?,
        cantidadInsumo: (map['cantidad_insumo'] as num?)?.toDouble() ?? 1.0,
      );
    }).toList();
  }

  Future<void> cancelSale(String ventaId) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // 1. Verificar estado actual de la venta
      final ventaRows = await txn.query('ventas', where: 'id = ?', whereArgs: [ventaId], limit: 1);
      if (ventaRows.isEmpty) throw Exception('Venta no encontrada');
      if (ventaRows.first['estatus'] == 'cancelado') throw Exception('El ticket ya está cancelado');

      // 2. Marcar como cancelado
      await txn.update(
        'ventas',
        {'estatus': 'cancelado'},
        where: 'id = ?',
        whereArgs: [ventaId],
      );

      // 3. Recuperar partidas para reintegrar stock (revisando si era servicio con insumo)
      final detalles = await txn.query('detalles_venta', where: 'venta_id = ?', whereArgs: [ventaId]);
      
      for (final item in detalles) {
        final prodId = item['producto_id'] as String;
        final qty = (item['cantidad'] as num).toDouble();

        if (prodId == 'ART-COMUN') continue;

        final prodRows = await txn.query(
          'productos',
          columns: ['id', 'es_servicio', 'insumo_vinculado_id', 'cantidad_insumo'],
          where: 'id = ?',
          whereArgs: [prodId],
          limit: 1,
        );

        if (prodRows.isNotEmpty) {
          final p = prodRows.first;
          final bool esServicio = (p['es_servicio'] as int? ?? 0) == 1;
          final String? insumoId = p['insumo_vinculado_id'] as String?;
          final double cantInsumo = (p['cantidad_insumo'] as num?)?.toDouble() ?? 1.0;

          if (esServicio && insumoId != null && insumoId.trim().isNotEmpty) {
            // Reintegrar al insumo vinculado
            final qtyToRestore = qty * cantInsumo;
            final insumoRows = await txn.query(
              'productos',
              columns: ['id', 'nombre', 'stock_actual'],
              where: 'id = ?',
              whereArgs: [insumoId],
              limit: 1,
            );
            final double currentStock = insumoRows.isNotEmpty ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0) : 0.0;
            final String insumoNombre = insumoRows.isNotEmpty ? (insumoRows.first['nombre'] as String? ?? insumoId) : insumoId;

            await txn.rawUpdate(
              'UPDATE productos SET stock_actual = stock_actual + ?, updated_at = ? WHERE id = ?',
              [qtyToRestore, isoNow, insumoId],
            );

            await _dbHelper.logInventoryMovement(
              db: txn,
              productoId: insumoId,
              productoDesc: insumoNombre,
              tipo: 'CANCELACION',
              cantidad: qtyToRestore,
              stockAnterior: currentStock,
              stockNuevo: currentStock + qtyToRestore,
              usuarioId: 'cajero',
              motivo: 'Cancelación total ticket $ventaId',
            );
          } else if (!esServicio) {
            // Reintegrar al producto físico
            final double currentStock = (p['stock_actual'] as num?)?.toDouble() ?? 0.0;
            final String prodNombre = p['nombre'] as String? ?? prodId;

            await txn.rawUpdate(
              'UPDATE productos SET stock_actual = stock_actual + ?, updated_at = ? WHERE id = ?',
              [qty, isoNow, prodId],
            );

            await _dbHelper.logInventoryMovement(
              db: txn,
              productoId: prodId,
              productoDesc: prodNombre,
              tipo: 'CANCELACION',
              cantidad: qty,
              stockAnterior: currentStock,
              stockNuevo: currentStock + qty,
              usuarioId: 'cajero',
              motivo: 'Cancelación total ticket $ventaId',
            );
          }
        }
      }

      // 4. Inserción en sync_queue
      final outboxPayload = jsonEncode({
        'venta_id': ventaId,
        'fecha_cancelacion': isoNow,
        'motivo': 'Cancelación desde caja',
      });

      await txn.insert(
        'sync_queue',
        {
          'id': 'CANC_$ventaId',
          'event_type': 'VENTA_CANCELADA',
          'payload': outboxPayload,
          'sync_status': 'pending',
          'created_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  /// Devolución parcial o total de partidas específicas de una venta
  Future<void> refundSaleItems({
    required String ventaId,
    required List<Map<String, dynamic>> itemsToRefund,
    required String motivo,
    required String usuarioId,
    String? corteCajaId,
  }) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      double totalReembolsado = 0.0;

      for (final refItem in itemsToRefund) {
        final String detalleId = refItem['detalle_id'] as String;
        final double cantidadDevolver = (refItem['cantidad'] as num).toDouble();
        if (cantidadDevolver <= 0) continue;

        final detRows = await txn.query(
          'detalles_venta',
          where: 'id = ? AND venta_id = ?',
          whereArgs: [detalleId, ventaId],
          limit: 1,
        );
        if (detRows.isEmpty) continue;
        final det = detRows.first;
        final double cantOriginal = (det['cantidad'] as num).toDouble();
        final double precioHist = (det['precio_historico'] as num).toDouble();
        final String prodId = det['producto_id'] as String;

        final double cantEfectivaDevolver = cantidadDevolver > cantOriginal ? cantOriginal : cantidadDevolver;
        final double subtotalLineaDevolver = cantEfectivaDevolver * precioHist;
        totalReembolsado += subtotalLineaDevolver;

        if (cantEfectivaDevolver >= cantOriginal) {
          await txn.update(
            'detalles_venta',
            {'cantidad': 0.0, 'total_linea': 0.0},
            where: 'id = ?',
            whereArgs: [detalleId],
          );
        } else {
          final double nuevaCant = cantOriginal - cantEfectivaDevolver;
          await txn.update(
            'detalles_venta',
            {'cantidad': nuevaCant, 'total_linea': nuevaCant * precioHist},
            where: 'id = ?',
            whereArgs: [detalleId],
          );
        }

        if (prodId != 'ART-COMUN') {
          final prodRows = await txn.query(
            'productos',
            columns: ['id', 'nombre', 'es_servicio', 'insumo_vinculado_id', 'cantidad_insumo', 'stock_actual'],
            where: 'id = ?',
            whereArgs: [prodId],
            limit: 1,
          );

          if (prodRows.isNotEmpty) {
            final p = prodRows.first;
            final bool esServicio = (p['es_servicio'] as int? ?? 0) == 1;
            final String? insumoId = p['insumo_vinculado_id'] as String?;
            final double cantInsumo = (p['cantidad_insumo'] as num?)?.toDouble() ?? 1.0;

            if (esServicio && insumoId != null && insumoId.trim().isNotEmpty) {
              final double qtyToRestore = cantEfectivaDevolver * cantInsumo;
              final insumoRows = await txn.query(
                'productos',
                columns: ['id', 'nombre', 'stock_actual'],
                where: 'id = ?',
                whereArgs: [insumoId],
                limit: 1,
              );
              final double currentStock = insumoRows.isNotEmpty ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0) : 0.0;
              final String insumoNombre = insumoRows.isNotEmpty ? (insumoRows.first['nombre'] as String? ?? insumoId) : insumoId;

              await txn.rawUpdate(
                'UPDATE productos SET stock_actual = stock_actual + ?, updated_at = ? WHERE id = ?',
                [qtyToRestore, isoNow, insumoId],
              );

              await _dbHelper.logInventoryMovement(
                db: txn,
                productoId: insumoId,
                productoDesc: insumoNombre,
                tipo: 'DEVOLUCION',
                cantidad: qtyToRestore,
                stockAnterior: currentStock,
                stockNuevo: currentStock + qtyToRestore,
                usuarioId: usuarioId,
                motivo: 'Devolución servicio ticket $ventaId: $motivo',
              );
            } else if (!esServicio) {
              final double currentStock = (p['stock_actual'] as num?)?.toDouble() ?? 0.0;
              final String prodNombre = p['nombre'] as String? ?? prodId;

              await txn.rawUpdate(
                'UPDATE productos SET stock_actual = stock_actual + ?, updated_at = ? WHERE id = ?',
                [cantEfectivaDevolver, isoNow, prodId],
              );

              await _dbHelper.logInventoryMovement(
                db: txn,
                productoId: prodId,
                productoDesc: prodNombre,
                tipo: 'DEVOLUCION',
                cantidad: cantEfectivaDevolver,
                stockAnterior: currentStock,
                stockNuevo: currentStock + cantEfectivaDevolver,
                usuarioId: usuarioId,
                motivo: 'Devolución ticket $ventaId: $motivo',
              );
            }
          }
        }
      }

      if (totalReembolsado > 0 && corteCajaId != null && corteCajaId.isNotEmpty) {
        await txn.insert('movimientos_caja', {
          'id': 'MOV_DEV_${DateTime.now().microsecondsSinceEpoch}',
          'corte_caja_id': corteCajaId,
          'tipo': 'salida',
          'monto': totalReembolsado,
          'concepto': 'Devolución mercancía ticket $ventaId: $motivo',
          'fecha': isoNow,
        });
      }

      await txn.rawUpdate('''
        UPDATE ventas 
        SET total = MAX(0.0, total - ?),
            subtotal = MAX(0.0, subtotal - ?)
        WHERE id = ?
      ''', [totalReembolsado, totalReembolsado, ventaId]);

      final remDetalles = await txn.rawQuery(
        'SELECT SUM(cantidad) as total_restante FROM detalles_venta WHERE venta_id = ?',
        [ventaId],
      );
      final double totalRestante = (remDetalles.first['total_restante'] as num?)?.toDouble() ?? 0.0;
      if (totalRestante <= 0.0) {
        await txn.update('ventas', {'estatus': 'cancelado'}, where: 'id = ?', whereArgs: [ventaId]);
      }
    });
  }
}