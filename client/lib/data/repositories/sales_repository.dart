import 'dart:async';



import 'dart:convert';



import 'package:sqflite/sqflite.dart';



import '../../core/string_utils.dart';



import '../local/database_helper.dart';



import '../local/models.dart';



import 'product_repository.dart';







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



  final double subtotal;



  final double descuentoTotal;



  final double ajusteRedondeo;



  final DateTime fechaVenta;



  final String estatus;



  final List<dynamic> pagosDesglose;



  final String clienteId;



  final String clienteNombre;



  final String corteCajaId;



  final String cajero;

  final String? notasTicket;







  SaleRecord({



    required this.id,



    required this.folioTicket,



    required this.total,



    double? subtotal,



    this.descuentoTotal = 0.0,



    this.ajusteRedondeo = 0.0,



    required this.fechaVenta,



    required this.estatus,



    required this.pagosDesglose,



    this.clienteId = 'PUBLICO-GRAL',



    this.clienteNombre = 'Público en General',



    this.corteCajaId = '',



    this.cajero = 'Caja 1',

    this.notasTicket,



  }) : subtotal = subtotal ?? total;







  factory SaleRecord.fromMap(Map<String, dynamic> map) {



    final t = (map['total'] as num).toDouble();



    return SaleRecord(



      id: map['id'] as String,



      folioTicket: map['folio_ticket'] as String? ?? 'S/F',



      total: t,



      subtotal: (map['subtotal'] as num?)?.toDouble() ?? t,



      descuentoTotal: (map['descuento_total'] as num?)?.toDouble() ?? 0.0,



      ajusteRedondeo: (map['ajuste_redondeo'] as num?)?.toDouble() ?? 0.0,



      fechaVenta: DateTime.parse(map['fecha_venta'] as String),



      estatus: map['estatus'] as String? ?? 'completado',



      pagosDesglose: jsonDecode(map['pagos_desglose'] as String? ?? '[]'),



      clienteId: map['cliente_id'] as String? ?? 'PUBLICO-GRAL',



      clienteNombre: map['cliente_nombre'] as String? ?? 'Público en General',



      corteCajaId: map['corte_caja_id'] as String? ?? '',



      cajero: map['usuario_id'] as String? ?? 'Caja 1',

      notasTicket: map['notas_ticket'] as String?,



    );



  }







  bool get isCancelado => estatus == 'cancelado';



  DateTime get fechaVentaLocal => fechaVenta.toLocal();







  String get primaryPaymentMethod {



    if (pagosDesglose.isEmpty) return 'Efectivo';



    if (pagosDesglose.length > 1) return 'Mixto';



    final method = (pagosDesglose.first['metodo'] as String? ?? 'efectivo').toLowerCase();



    if (method.contains('efectivo')) return 'Efectivo';



    if (method.contains('tarjeta')) return 'Tarjeta';



    if (method.contains('transfer')) return 'Transferencia';



    if (method.contains('credito')) return 'Crédito';



    return method.toUpperCase();



  }



}







class SalesRepository {



  final DatabaseHelper _dbHelper;







  SalesRepository({DatabaseHelper? dbHelper})



      : _dbHelper = dbHelper ?? DatabaseHelper.instance;







  // ===========================================================================



  // 1. TRANSACCIÓN ATÓMICA DE VENTA (ACID + DYNAMIC RUNTIME BOM + OUTBOX)



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



          'cliente_id': sale.clienteId,



          'cliente_nombre': sale.clienteNombre,



          'folio_ticket': sale.folioTicket,



          'subtotal': sale.subtotal,



          'descuento_total': sale.descuentoTotal,



          'impuestos_total': sale.impuestosTotal,



          'total': sale.total,



          'ajuste_redondeo': sale.ajusteRedondeo,



          'pagos_desglose': jsonEncode(sale.pagosDesglose.map((p) => p.toJson()).toList()),



          'fecha_venta': isoNow,



          'estatus': 'completado',

          'notas_ticket': sale.notasTicket,



        },



        conflictAlgorithm: ConflictAlgorithm.abort,



      );







      final List<Map<String, dynamic>> insumosDescontadosLog = [];



      final List<SaleDetailItem> processedItems = [];







      // 2. Inserción de cada Partida y Descuento Atómico de Stock / Insumo Dinámico



      for (final item in sale.items) {



        // Caso especial: Artículo Común no afecta inventario físico



        if (item.productoId == 'ART-COMUN') {



          await txn.insert(



            'detalles_venta',



            item.toMap(sale.ventaId),



            conflictAlgorithm: ConflictAlgorithm.abort,



          );



          processedItems.add(item);



          continue;



        }







        // Consultar atributos del producto o servicio principal



        final prodRows = await txn.query(



          'productos',



          columns: [



            'id',



            'es_servicio',



            'insumo_vinculado_id',



            'cantidad_insumo',



            'nombre',



            'stock_actual',



            'precio_compra',



            'departamento',



          ],



          where: 'id = ?',



          whereArgs: [item.productoId],



          limit: 1,



        );







        // A. SERVICIO CON VINCULACIÓN DINÁMICA DE INSUMO EN CAJA (Dynamic Runtime BOM)



        if (item.hasDynamicInsumo) {



          final String insumoId = item.insumoUtilizadoId!.trim();



          final double cantidadConsumida = item.cantidadInsumoConsumida;







          final insumoRows = await txn.query(



            'productos',



            columns: ['id', 'nombre', 'stock_actual', 'precio_compra', 'departamento'],



            where: 'id = ?',



            whereArgs: [insumoId],



            limit: 1,



          );







          final double currentInsumoStock = insumoRows.isNotEmpty



              ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



              : 0.0;



          final double costoUnitarioInsumo = insumoRows.isNotEmpty



              ? ((insumoRows.first['precio_compra'] as num?)?.toDouble() ?? 0.0)



              : 0.0;



          final String insumoNombre = insumoRows.isNotEmpty



              ? (insumoRows.first['nombre'] as String? ?? item.insumoUtilizadoNombre ?? insumoId)



              : (item.insumoUtilizadoNombre ?? insumoId);



          final String? insumoDepto = insumoRows.isNotEmpty



              ? insumoRows.first['departamento'] as String?



              : null;







          // Costo real de la llave utilizada: costoUnitarioInsumo * cantidadInsumoConsumida.



          // Se normaliza por item.cantidad para que costo_historico * cantidad en reportes



          // sea exactamente igual a costoUnitarioInsumo * cantidadInsumoConsumida.



          final double costoTotalInsumo = costoUnitarioInsumo * cantidadConsumida;



          final double costoHistoricoEfectivo =



              item.cantidad > 0 ? (costoTotalInsumo / item.cantidad) : costoTotalInsumo;







          final effectiveItem = item.copyWith(costoHistorico: costoHistoricoEfectivo);







          await txn.insert(



            'detalles_venta',



            effectiveItem.toMap(sale.ventaId),



            conflictAlgorithm: ConflictAlgorithm.abort,



          );



          processedItems.add(effectiveItem);







          final double newInsumoStock = currentInsumoStock - cantidadConsumida;







          final updatedRows = await txn.rawUpdate('''



            UPDATE productos 



            SET stock_actual = stock_actual - ?,



                ventas_ultimos_30dias = COALESCE(ventas_ultimos_30dias, 0) + ?,



                total_unidades_vendidas = COALESCE(total_unidades_vendidas, 0) + ?,



                ultima_venta_at = ?,



                updated_at = ?



            WHERE id = ?



          ''', [cantidadConsumida, cantidadConsumida, cantidadConsumida, isoNow, isoNow, insumoId]);







          if (updatedRows == 0) {



            throw Exception('Insumo físico utilizado ($insumoId) no encontrado en catálogo.');



          }







          await _dbHelper.logInventoryMovement(



            db: txn,



            productoId: insumoId,



            productoDesc: insumoNombre,



            tipo: 'VENTA_SERVICIO',



            cantidad: cantidadConsumida,



            stockAnterior: currentInsumoStock,



            stockNuevo: newInsumoStock,



            usuarioId: 'cajero',



            departamento: insumoDepto,



            motivo: newInsumoStock < 0



                ? 'VENTA EN NEGATIVO (Sobregiro autorizado) - Insumo de ${item.nombre} (Folio ${sale.folioTicket ?? sale.ventaId})'



                : 'Consumo por servicio: ${item.nombre} (Folio ${sale.folioTicket ?? sale.ventaId})',



          );







          insumosDescontadosLog.add({



            'servicio_id': item.productoId,



            'insumo_id': insumoId,



            'insumo_nombre': insumoNombre,



            'cantidad_servicio': item.cantidad,



            'cantidad_insumo_descontada': cantidadConsumida,



            'costo_unitario_insumo': costoUnitarioInsumo,



            'costo_total_insumo': costoTotalInsumo,



          });



          continue;



        }







        // Insertar partida estándar o servicio puro / legacy



        await txn.insert(



          'detalles_venta',



          item.toMap(sale.ventaId),



          conflictAlgorithm: ConflictAlgorithm.abort,



        );



        processedItems.add(item);







        if (prodRows.isNotEmpty) {



          final prod = prodRows.first;



          final bool esServicio = (prod['es_servicio'] as int? ?? 0) == 1;



          final String? insumoId = prod['insumo_vinculado_id'] as String?;



          final double cantInsumo = (prod['cantidad_insumo'] as num?)?.toDouble() ?? 1.0;



          final String prodNombre = (prod['nombre'] as String?) ?? item.nombre;



          final String? depto = prod['departamento'] as String?;







          if (esServicio && insumoId != null && insumoId.trim().isNotEmpty) {



            // Compatibilidad legacy con servicios de insumo fijo



            final double cantidadADescontar = item.cantidad * cantInsumo;







            final insumoRows = await txn.query(



              'productos',



              columns: ['id', 'nombre', 'stock_actual', 'departamento'],



              where: 'id = ?',



              whereArgs: [insumoId],



              limit: 1,



            );



            final double currentInsumoStock = insumoRows.isNotEmpty



                ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



                : 0.0;



            final String insumoNombre = insumoRows.isNotEmpty



                ? (insumoRows.first['nombre'] as String? ?? insumoId)



                : insumoId;



            final String? insumoDepto = insumoRows.isNotEmpty



                ? insumoRows.first['departamento'] as String?



                : null;



            final double newInsumoStock = currentInsumoStock - cantidadADescontar;







            final updatedRows = await txn.rawUpdate('''



              UPDATE productos 



              SET stock_actual = stock_actual - ?,



                  ventas_ultimos_30dias = COALESCE(ventas_ultimos_30dias, 0) + ?,



                  total_unidades_vendidas = COALESCE(total_unidades_vendidas, 0) + ?,



                  ultima_venta_at = ?,



                  updated_at = ?



              WHERE id = ?



            ''', [cantidadADescontar, cantidadADescontar, cantidadADescontar, isoNow, isoNow, insumoId]);







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



              motivo: newInsumoStock < 0



                  ? 'VENTA EN NEGATIVO (Sobregiro autorizado en caja) - Insumo de servicio $prodNombre (Folio ${sale.folioTicket ?? sale.ventaId})'



                  : 'Consumo por servicio: $prodNombre (Folio ${sale.folioTicket ?? sale.ventaId})',



            );







            insumosDescontadosLog.add({



              'servicio_id': item.productoId,



              'insumo_id': insumoId,



              'cantidad_servicio': item.cantidad,



              'cantidad_insumo_descontada': cantidadADescontar,



            });



          } else if (!esServicio) {



            // Producto físico normal: descuenta su propio stock y actualiza velocidad de venta



            final double currentStock = (prod['stock_actual'] as num?)?.toDouble() ?? 0.0;



            final double newStock = currentStock - item.cantidad;







            final updatedRows = await txn.rawUpdate('''



              UPDATE productos 



              SET stock_actual = stock_actual - ?,



                  ventas_ultimos_30dias = COALESCE(ventas_ultimos_30dias, 0) + ?,



                  total_unidades_vendidas = COALESCE(total_unidades_vendidas, 0) + ?,



                  ultima_venta_at = ?,



                  updated_at = ?



              WHERE id = ?



            ''', [item.cantidad, item.cantidad, item.cantidad, isoNow, isoNow, item.productoId]);







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



              motivo: newStock < 0



                  ? 'VENTA EN NEGATIVO (Sobregiro autorizado en caja) - Folio ${sale.folioTicket ?? sale.ventaId}'



                  : 'Venta Folio ${sale.folioTicket ?? sale.ventaId}',



            );



          }



          // Si es servicio puro sin insumo vinculado (ej. Apertura, Reparación), no modifica inventario físico.



        } else if (!item.esServicio) {



          // Fallback solo si no es servicio



          await txn.rawUpdate('''



            UPDATE productos 



            SET stock_actual = stock_actual - ?, 



                updated_at = ? 



            WHERE id = ?



          ''', [item.cantidad, isoNow, item.productoId]);



        }



      }







      // 2.1 Afectación de Crédito al Cliente (Incremento atómico de saldo_deudor)



      final double totalCredito = sale.pagosDesglose



          .where((p) => p.metodo.toLowerCase().contains('crédit') || p.metodo.toLowerCase().contains('credit'))



          .fold<double>(0.0, (acc, p) => acc + p.monto);







      if (totalCredito > 0 && sale.clienteId != 'PUBLICO-GRAL') {



        await txn.rawUpdate('''



          UPDATE clientes 



          SET saldo_deudor = COALESCE(saldo_deudor, 0.0) + ? 



          WHERE id = ?;



        ''', [totalCredito, sale.clienteId]);



      }







      // 3. Empaquetado del Evento Outbox con desglose de insumos consumidos



      final outboxPayload = jsonEncode({



        'venta_id': sale.ventaId,



        'corte_caja_id': sale.corteCajaId,



        'cliente_id': sale.clienteId,



        'cliente_nombre': sale.clienteNombre,



        'folio_ticket': sale.folioTicket,



        'totales': {



          'subtotal': sale.subtotal,



          'descuentos': sale.descuentoTotal,



          'impuestos': sale.impuestosTotal,



          'total': sale.total,



          'ajuste_redondeo': sale.ajusteRedondeo,



        },



        'pagos': sale.pagosDesglose.map((p) => p.toJson()).toList(),



        'items': processedItems.map((i) => i.toJson()).toList(),



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



  // 2. MOTOR DE BÚSQUEDA INTELIGENTE, COMODÍN % Y SERVICIOS POR DEPARTAMENTO



  // ===========================================================================







  /// Obtiene todos los servicios activos cuyos `departamentos_aplicables` incluyan



  /// el departamento del producto seleccionado (o `'Todos'`).



  Future<List<Product>> getApplicableServicesForDepartment(String departamento) async {



    final db = await _dbHelper.database;



    final rows = await db.query(



      'productos',



      where: 'es_servicio = 1',



      orderBy: 'precio_venta ASC, nombre ASC',



    );



    final allServices = rows.map((r) => Product.fromMap(r)).toList();



    return allServices.where((srv) => srv.appliesToDepartment(departamento)).toList();



  }







  /// Guarda un nuevo servicio personalizado en el catálogo local y encola en outbox



  Future<void> saveCustomService(Product service) async {



    final productRepo = ProductRepository(dbHelper: _dbHelper);



    await productRepo.saveProduct(service);



  }







  /// Obtiene la lista de nombres de departamentos únicos en el catálogo



  Future<List<String>> getDepartmentNames() async {



    final db = await _dbHelper.database;



    final results = await db.rawQuery(



      'SELECT DISTINCT departamento FROM productos WHERE departamento IS NOT NULL AND departamento != "" ORDER BY departamento ASC',



    );



    return results.map((r) => r['departamento'] as String).toList();



  }







  Future<Product?> findProductById(String id) async {



    final db = await _dbHelper.database;



    final results = await db.query(



      'productos',



      where: 'id = ?',



      whereArgs: [id],



      limit: 1,



    );



    if (results.isNotEmpty) {



      return Product.fromMap(results.first);



    }



    return null;



  }







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







    // Soporte especializado para búsqueda directa por Molde (Cross-Reference): 'molde:R52'



    if (cleanQuery.toLowerCase().startsWith('molde:')) {



      final moldTerm = cleanQuery.safeSub(6).trim().toUpperCase();



      if (moldTerm.isEmpty) return [];







      final moldRows = await db.rawQuery('''



        SELECT * FROM productos



        WHERE UPPER(codigo_equivalencia) = ?



        ORDER BY (CASE WHEN stock_actual > 0 THEN 0 ELSE 1 END) ASC, 



                 stock_actual DESC, 



                 marca ASC, 



                 nombre ASC



        LIMIT ?



      ''', [moldTerm, limit]);







      return moldRows.map((r) => Product.fromMap(r)).toList();



    }







    final bool isDeepSearch = cleanQuery.startsWith('%');



    final String searchTerm = isDeepSearch ? cleanQuery.safeSub(1).trim() : cleanQuery;







    if (searchTerm.isEmpty) return [];







    List<Map<String, dynamic>> directRows = [];







    if (isDeepSearch) {



      final pattern = '%$searchTerm%';



      directRows = await db.rawQuery('''



        SELECT * FROM productos



        WHERE descripcion LIKE ? 



           OR nombre LIKE ? 



           OR sku LIKE ? 



           OR marca LIKE ? 



           OR codigo_barras LIKE ?



           OR codigo_equivalencia LIKE ?



           OR departamento LIKE ?



        LIMIT ?



      ''', [pattern, pattern, pattern, pattern, pattern, pattern, pattern, limit]);



    } else {



      final pattern = '%$searchTerm%';



      directRows = await db.rawQuery('''



        SELECT * FROM productos



        WHERE codigo_barras = ? 



           OR sku = ? 



           OR sku LIKE ? 



           OR nombre LIKE ? 



           OR marca LIKE ?



           OR codigo_equivalencia = ?



           OR codigo_equivalencia LIKE ?



        LIMIT ?



      ''', [searchTerm, searchTerm, pattern, pattern, pattern, searchTerm, pattern, limit]);



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



    return 9;



  }







  // Compatibilidad con invocaciones legacy



  Future<List<Product>> searchProductsByDescription(String query, {int limit = 15}) async {



    return searchProductsAdvanced(query, limit: limit);



  }







  // ===========================================================================



  // 3. HISTORIAL Y DEVOLUCIONES (CAJ-07 CON REVERSIÓN DE INSUMOS DINÁMICOS)



  // ===========================================================================







  Future<List<SaleRecord>> getSalesHistory({

    String query = '',

    DateTime? startDate,

    DateTime? endDate,

    String? estatus,

    int limit = 300,

  }) async {

    final db = await _dbHelper.database;

    final cleanQuery = query.trim();



    final List<String> conditions = [];

    final List<dynamic> whereArgs = [];



    if (cleanQuery.isNotEmpty) {

      conditions.add('(folio_ticket LIKE ? OR id = ? OR cliente_nombre LIKE ?)');

      whereArgs.addAll(['%$cleanQuery%', cleanQuery, '%$cleanQuery%']);

    }



    if (startDate != null) {

      conditions.add("fecha_venta >= ?");

      whereArgs.add(startDate.toIso8601String());

    }



    if (endDate != null) {

      conditions.add("fecha_venta <= ?");

      whereArgs.add(endDate.toIso8601String());

    }



    if (estatus != null && estatus != 'todos') {

      conditions.add("estatus = ?");

      whereArgs.add(estatus);

    }



    final String? whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;



    final results = await db.query(

      'ventas',

      where: whereClause,

      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,

      orderBy: 'fecha_venta DESC',

      limit: limit,

    );



    return results.map((r) => SaleRecord.fromMap(r)).toList();

  }







  /// Consulta movimientos de inventario en rango de fechas
  Future<List<Map<String, dynamic>>> getInventoryMovements({
    DateTime? startDate,
    DateTime? endDate,
    String? query,
    int limit = 300,
  }) async {
    final db = await _dbHelper.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClauses.add('fecha >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClauses.add('fecha <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    if (query != null && query.trim().isNotEmpty) {
      whereClauses.add('(producto_desc LIKE ? OR producto_id LIKE ? OR motivo LIKE ?)');
      final term = '%${query.trim()}%';
      whereArgs.addAll([term, term, term]);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    return await db.query(
      'movimientos_inventario',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'fecha DESC',
      limit: limit,
    );
  }

  /// Consulta movimientos de caja (entradas y salidas)
  Future<List<Map<String, dynamic>>> getCashMovements({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 300,
  }) async {
    final db = await _dbHelper.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClauses.add('fecha >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClauses.add('fecha <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;
    return await db.query(
      'movimientos_caja',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'fecha DESC',
      limit: limit,
    );
  }

  /// Consulta abonos a crédito de clientes
  Future<List<Map<String, dynamic>>> getCreditPayments({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 300,
  }) async {
    final db = await _dbHelper.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClauses.add('a.fecha >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClauses.add('a.fecha <= ?');
      whereArgs.add(endDate.toIso8601String());
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
    return await db.rawQuery('''
      SELECT a.*, c.nombre as cliente_nombre
      FROM abonos_credito a
      LEFT JOIN clientes c ON a.cliente_id = c.id
      $whereString
      ORDER BY a.fecha DESC
      LIMIT ?
    ''', [...whereArgs, limit]);
  }

  Future<List<SaleDetailItem>> getSaleDetails(String ventaId) async {



    final db = await _dbHelper.database;



    final results = await db.rawQuery('''



      SELECT d.*,



             p.nombre AS prod_nombre,



             p.descripcion AS prod_descripcion,



             p.ubicacion AS prod_ubicacion,



             p.sku AS prod_sku,



             p.marca AS prod_marca,



             p.es_servicio AS prod_es_servicio,



             p.insumo_vinculado_id AS prod_insumo_vinculado_id,



             p.cantidad_insumo AS prod_cantidad_insumo,



             ins.nombre AS insumo_nombre,



             ins.sku AS insumo_sku,



             ins.ubicacion AS insumo_ubicacion



      FROM detalles_venta d



      LEFT JOIN productos p ON d.producto_id = p.id



      LEFT JOIN productos ins ON d.insumo_utilizado_id = ins.id



      WHERE d.venta_id = ?



    ''', [ventaId]);







    return results.map((map) {



      final String baseDesc = (map['prod_descripcion'] as String?) ?? 'Producto ${map['producto_id']}';



      final String baseNom = (map['prod_nombre'] as String?) ?? baseDesc;



      final String? insumoId = map['insumo_utilizado_id'] as String?;



      final String? insumoNom = map['insumo_nombre'] as String?;



      final String? insumoSku = map['insumo_sku'] as String?;



      final double cantInsumoCons = (map['cantidad_insumo_consumida'] as num?)?.toDouble() ?? 0.0;







      final bool hasDynamicInsumo = insumoId != null && insumoId.trim().isNotEmpty;



      final String displayNom = hasDynamicInsumo && insumoNom != null && insumoNom.isNotEmpty



          ? '$baseNom ($insumoNom)'



          : baseNom;



      final String displayDesc = hasDynamicInsumo && insumoNom != null && insumoNom.isNotEmpty



          ? '$baseNom - $insumoNom'



          : baseDesc;







      return SaleDetailItem(



        id: map['id'] as String,



        productoId: map['producto_id'] as String,



        nombre: displayNom,



        descripcion: displayDesc,



        cantidad: (map['cantidad'] as num).toDouble(),



        precioHistorico: (map['precio_historico'] as num).toDouble(),



        totalLinea: (map['total_linea'] as num).toDouble(),



        costoHistorico: (map['costo_historico'] as num?)?.toDouble() ?? 0.0,



        descuentoLinea: (map['descuento_linea'] as num?)?.toDouble() ?? 0.0,



        ubicacion: (map['insumo_ubicacion'] as String?) ?? (map['prod_ubicacion'] as String?),



        sku: map['prod_sku'] as String?,



        marca: map['prod_marca'] as String?,



        esServicio: (map['prod_es_servicio'] as int? ?? 0) == 1,



        insumoVinculadoId: map['prod_insumo_vinculado_id'] as String?,



        cantidadInsumo: (map['prod_cantidad_insumo'] as num?)?.toDouble() ?? 1.0,



        insumoUtilizadoId: insumoId,



        insumoUtilizadoNombre: insumoNom,



        insumoUtilizadoSku: insumoSku,



        cantidadInsumoConsumida: cantInsumoCons,



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







      // 2.1 Si la venta fue a crédito, descontar del saldo_deudor del cliente



      final String? clienteId = ventaRows.first['cliente_id'] as String?;



      final String pagosDesgloseStr = ventaRows.first['pagos_desglose'] as String? ?? '[]';



      if (clienteId != null && clienteId != 'PUBLICO-GRAL') {



        double montoCreditoEnVenta = 0.0;



        try {



          final List<dynamic> pagosList = jsonDecode(pagosDesgloseStr);



          for (final p in pagosList) {



            final metodo = (p['metodo'] as String? ?? '').toLowerCase();



            if (metodo.contains('credit') || metodo.contains('crédit')) {



              montoCreditoEnVenta += (p['monto'] as num?)?.toDouble() ?? 0.0;



            }



          }



        } catch (_) {}







        if (montoCreditoEnVenta > 0) {



          await txn.rawUpdate(



            'UPDATE clientes SET saldo_deudor = MAX(0, saldo_deudor - ?) WHERE id = ?',



            [montoCreditoEnVenta, clienteId],



          );



        }



      }







      // 3. Recuperar partidas para reintegrar stock (priorizando insumo_utilizado_id dinámico)



      final detalles = await txn.query('detalles_venta', where: 'venta_id = ?', whereArgs: [ventaId]);







      for (final item in detalles) {



        final prodId = item['producto_id'] as String;



        final qty = (item['cantidad'] as num).toDouble();



        final String? dynInsumoId = item['insumo_utilizado_id'] as String?;



        final double dynCantConsumida = (item['cantidad_insumo_consumida'] as num?)?.toDouble() ?? 0.0;







        if (prodId == 'ART-COMUN') continue;







        // A. Reintegrar insumo físico vinculado dinámicamente en caja



        if (dynInsumoId != null && dynInsumoId.trim().isNotEmpty && dynCantConsumida > 0) {



          final cleanInsumoId = dynInsumoId.trim();



          final insumoRows = await txn.query(



            'productos',



            columns: ['id', 'nombre', 'stock_actual', 'departamento'],



            where: 'id = ?',



            whereArgs: [cleanInsumoId],



            limit: 1,



          );



          final double currentStock = insumoRows.isNotEmpty



              ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



              : 0.0;



          final String insumoNombre = insumoRows.isNotEmpty



              ? (insumoRows.first['nombre'] as String? ?? cleanInsumoId)



              : cleanInsumoId;



          final String? insumoDepto = insumoRows.isNotEmpty



              ? insumoRows.first['departamento'] as String?



              : null;







          await txn.rawUpdate('''



            UPDATE productos



            SET stock_actual = stock_actual + ?,



                ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                updated_at = ?



            WHERE id = ?



          ''', [dynCantConsumida, dynCantConsumida, dynCantConsumida, isoNow, cleanInsumoId]);







          await _dbHelper.logInventoryMovement(



            db: txn,



            productoId: cleanInsumoId,



            productoDesc: insumoNombre,



            tipo: 'CANCELACION',



            cantidad: dynCantConsumida,



            stockAnterior: currentStock,



            stockNuevo: currentStock + dynCantConsumida,



            usuarioId: 'cajero',



            departamento: insumoDepto,



            motivo: 'Cancelación total ticket $ventaId (reintegro de insumo de servicio)',



          );



          continue;



        }







        // B. Producto físico estándar o servicio legacy con insumo fijo



        final prodRows = await txn.query(



          'productos',



          columns: ['id', 'nombre', 'es_servicio', 'insumo_vinculado_id', 'cantidad_insumo', 'stock_actual', 'departamento'],



          where: 'id = ?',



          whereArgs: [prodId],



          limit: 1,



        );







        if (prodRows.isNotEmpty) {



          final p = prodRows.first;



          final bool esServicio = (p['es_servicio'] as int? ?? 0) == 1;



          final String? insumoId = p['insumo_vinculado_id'] as String?;



          final double cantInsumo = (p['cantidad_insumo'] as num?)?.toDouble() ?? 1.0;







          if (esServicio && insumoId != null && insumoId.trim().isNotEmpty && qty > 0) {



            final qtyToRestore = qty * cantInsumo;



            final insumoRows = await txn.query(



              'productos',



              columns: ['id', 'nombre', 'stock_actual', 'departamento'],



              where: 'id = ?',



              whereArgs: [insumoId],



              limit: 1,



            );



            final double currentStock = insumoRows.isNotEmpty



                ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



                : 0.0;



            final String insumoNombre = insumoRows.isNotEmpty



                ? (insumoRows.first['nombre'] as String? ?? insumoId)



                : insumoId;



            final String? insumoDepto = insumoRows.isNotEmpty



                ? insumoRows.first['departamento'] as String?



                : null;







            await txn.rawUpdate('''



              UPDATE productos



              SET stock_actual = stock_actual + ?,



                  ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                  total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                  updated_at = ?



              WHERE id = ?



            ''', [qtyToRestore, qtyToRestore, qtyToRestore, isoNow, insumoId]);







            await _dbHelper.logInventoryMovement(



              db: txn,



              productoId: insumoId,



              productoDesc: insumoNombre,



              tipo: 'CANCELACION',



              cantidad: qtyToRestore,



              stockAnterior: currentStock,



              stockNuevo: currentStock + qtyToRestore,



              usuarioId: 'cajero',



              departamento: insumoDepto,



              motivo: 'Cancelación total ticket $ventaId',



            );



          } else if (!esServicio && qty > 0) {



            final double currentStock = (p['stock_actual'] as num?)?.toDouble() ?? 0.0;



            final String prodNombre = p['nombre'] as String? ?? prodId;



            final String? depto = p['departamento'] as String?;







            await txn.rawUpdate('''



              UPDATE productos



              SET stock_actual = stock_actual + ?,



                  ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                  total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                  updated_at = ?



              WHERE id = ?



            ''', [qty, qty, qty, isoNow, prodId]);







            await _dbHelper.logInventoryMovement(



              db: txn,



              productoId: prodId,



              productoDesc: prodNombre,



              tipo: 'CANCELACION',



              cantidad: qty,



              stockAnterior: currentStock,



              stockNuevo: currentStock + qty,



              usuarioId: 'cajero',



              departamento: depto,



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



        conflictAlgorithm: ConflictAlgorithm.replace,



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



      final List<Map<String, dynamic>> stockAdjustmentsToSync = [];







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



        if (cantOriginal <= 0) continue;







        final double precioHist = (det['precio_historico'] as num).toDouble();



        final String prodId = det['producto_id'] as String;



        final String? dynInsumoId = det['insumo_utilizado_id'] as String?;



        final double dynCantOrig = (det['cantidad_insumo_consumida'] as num?)?.toDouble() ?? 0.0;







        final double cantEfectivaDevolver =



            cantidadDevolver > cantOriginal ? cantOriginal : cantidadDevolver;



        final double subtotalLineaDevolver = cantEfectivaDevolver * precioHist;



        totalReembolsado += subtotalLineaDevolver;







        final bool hasDynamicInsumo =



            dynInsumoId != null && dynInsumoId.trim().isNotEmpty && dynCantOrig > 0;



        final double ratio = cantOriginal > 0 ? (cantEfectivaDevolver / cantOriginal) : 1.0;



        final double dynQtyToRestore = hasDynamicInsumo



            ? (cantEfectivaDevolver >= cantOriginal ? dynCantOrig : (dynCantOrig * ratio))



            : 0.0;







        if (cantEfectivaDevolver >= cantOriginal) {



          await txn.update(



            'detalles_venta',



            {



              'cantidad': 0.0,



              'total_linea': 0.0,



              if (hasDynamicInsumo) 'cantidad_insumo_consumida': 0.0,



            },



            where: 'id = ?',



            whereArgs: [detalleId],



          );



        } else {



          final double nuevaCant = cantOriginal - cantEfectivaDevolver;



          await txn.update(



            'detalles_venta',



            {



              'cantidad': nuevaCant,



              'total_linea': nuevaCant * precioHist,



              if (hasDynamicInsumo)



                'cantidad_insumo_consumida': (dynCantOrig - dynQtyToRestore).clamp(0.0, dynCantOrig),



            },



            where: 'id = ?',



            whereArgs: [detalleId],



          );



        }







        if (prodId == 'ART-COMUN') continue;







        // A. Devolución de Servicio con Insumo Dinámico -> Reintegrar piezas físicas de la llave



        if (hasDynamicInsumo && dynQtyToRestore > 0) {



          final cleanInsumoId = dynInsumoId.trim();



          final insumoRows = await txn.query(



            'productos',



            columns: ['id', 'nombre', 'stock_actual', 'departamento'],



            where: 'id = ?',



            whereArgs: [cleanInsumoId],



            limit: 1,



          );



          final double currentStock = insumoRows.isNotEmpty



              ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



              : 0.0;



          final String insumoNombre = insumoRows.isNotEmpty



              ? (insumoRows.first['nombre'] as String? ?? cleanInsumoId)



              : cleanInsumoId;



          final String? insumoDepto = insumoRows.isNotEmpty



              ? insumoRows.first['departamento'] as String?



              : null;



          final double newStock = currentStock + dynQtyToRestore;







          await txn.rawUpdate('''



            UPDATE productos



            SET stock_actual = stock_actual + ?,



                ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                updated_at = ?



            WHERE id = ?



          ''', [dynQtyToRestore, dynQtyToRestore, dynQtyToRestore, isoNow, cleanInsumoId]);







          await _dbHelper.logInventoryMovement(



            db: txn,



            productoId: cleanInsumoId,



            productoDesc: insumoNombre,



            tipo: 'DEVOLUCION',



            cantidad: dynQtyToRestore,



            stockAnterior: currentStock,



            stockNuevo: newStock,



            usuarioId: usuarioId,



            departamento: insumoDepto,



            motivo: 'Devolución servicio ticket $ventaId: $motivo',



          );







          stockAdjustmentsToSync.add({



            'producto_id': cleanInsumoId,



            'stock_teorico': currentStock,



            'stock_fisico': newStock,



            'diferencia': dynQtyToRestore,



          });



          continue;



        }







        // B. Producto físico normal o servicio legacy



        final prodRows = await txn.query(



          'productos',



          columns: ['id', 'nombre', 'es_servicio', 'insumo_vinculado_id', 'cantidad_insumo', 'stock_actual', 'departamento'],



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



              columns: ['id', 'nombre', 'stock_actual', 'departamento'],



              where: 'id = ?',



              whereArgs: [insumoId],



              limit: 1,



            );



            final double currentStock = insumoRows.isNotEmpty



                ? ((insumoRows.first['stock_actual'] as num?)?.toDouble() ?? 0.0)



                : 0.0;



            final String insumoNombre = insumoRows.isNotEmpty



                ? (insumoRows.first['nombre'] as String? ?? insumoId)



                : insumoId;



            final String? insumoDepto = insumoRows.isNotEmpty



                ? insumoRows.first['departamento'] as String?



                : null;



            final double newStock = currentStock + qtyToRestore;







            await txn.rawUpdate('''



              UPDATE productos



              SET stock_actual = stock_actual + ?,



                  ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                  total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                  updated_at = ?



              WHERE id = ?



            ''', [qtyToRestore, qtyToRestore, qtyToRestore, isoNow, insumoId]);







            await _dbHelper.logInventoryMovement(



              db: txn,



              productoId: insumoId,



              productoDesc: insumoNombre,



              tipo: 'DEVOLUCION',



              cantidad: qtyToRestore,



              stockAnterior: currentStock,



              stockNuevo: newStock,



              usuarioId: usuarioId,



              departamento: insumoDepto,



              motivo: 'Devolución servicio ticket $ventaId: $motivo',



            );







            stockAdjustmentsToSync.add({



              'producto_id': insumoId,



              'stock_teorico': currentStock,



              'stock_fisico': newStock,



              'diferencia': qtyToRestore,



            });



          } else if (!esServicio) {



            final double currentStock = (p['stock_actual'] as num?)?.toDouble() ?? 0.0;



            final String prodNombre = p['nombre'] as String? ?? prodId;



            final String? depto = p['departamento'] as String?;



            final double newStock = currentStock + cantEfectivaDevolver;







            await txn.rawUpdate('''



              UPDATE productos



              SET stock_actual = stock_actual + ?,



                  ventas_ultimos_30dias = MAX(0, COALESCE(ventas_ultimos_30dias, 0) - ?),



                  total_unidades_vendidas = MAX(0, COALESCE(total_unidades_vendidas, 0) - ?),



                  updated_at = ?



              WHERE id = ?



            ''', [cantEfectivaDevolver, cantEfectivaDevolver, cantEfectivaDevolver, isoNow, prodId]);







            await _dbHelper.logInventoryMovement(



              db: txn,



              productoId: prodId,



              productoDesc: prodNombre,



              tipo: 'DEVOLUCION',



              cantidad: cantEfectivaDevolver,



              stockAnterior: currentStock,



              stockNuevo: newStock,



              usuarioId: usuarioId,



              departamento: depto,



              motivo: 'Devolución ticket $ventaId: $motivo',



            );







            stockAdjustmentsToSync.add({



              'producto_id': prodId,



              'stock_teorico': currentStock,



              'stock_fisico': newStock,



              'diferencia': cantEfectivaDevolver,



            });



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



        // Sincronizar cancelación total al backend



        await txn.insert(



          'sync_queue',



          {



            'id': 'CANC_$ventaId',



            'event_type': 'VENTA_CANCELADA',



            'payload': jsonEncode({



              'venta_id': ventaId,



              'fecha_cancelacion': isoNow,



              'motivo': 'Devolución total: $motivo',



            }),



            'sync_status': 'pending',



            'created_at': isoNow,



          },



          conflictAlgorithm: ConflictAlgorithm.replace,



        );



      } else {



        // Sincronizar reintegro parcial de stock al backend



        int seq = 0;



        for (final adj in stockAdjustmentsToSync) {



          seq++;



          final adjId = 'DEV_${ventaId}_${DateTime.now().microsecondsSinceEpoch}_$seq';



          await txn.insert(



            'sync_queue',



            {



              'id': adjId,



              'event_type': 'AJUSTE_INVENTARIO',



              'payload': jsonEncode({



                'ajuste_id': adjId,



                'producto_id': adj['producto_id'],



                'stock_teorico': adj['stock_teorico'],



                'stock_fisico': adj['stock_fisico'],



                'diferencia': adj['diferencia'],



                'motivo': 'Devolución parcial ticket $ventaId: $motivo',



                'autorizado_por': usuarioId,



                'fecha_ajuste': isoNow,



              }),



              'sync_status': 'pending',



              'created_at': isoNow,



            },



            conflictAlgorithm: ConflictAlgorithm.replace,



          );



        }



      }



    });



  }



}



