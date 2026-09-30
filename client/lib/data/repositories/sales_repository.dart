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
  // 1. TRANSACCIÓN ATÓMICA DE VENTA (ACID + OUTBOX PATTERN)
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
          'estatus': 'completado' // Campo agregado para CAJ-07
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      // 2. Inserción de cada Partida y Reducción de Stock Decimal
      for (final item in sale.items) {
        await txn.insert(
          'detalles_venta',
          item.toMap(sale.ventaId),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final updatedRows = await txn.rawUpdate('''
          UPDATE productos 
          SET stock_actual = stock_actual - ?, 
              updated_at = ? 
          WHERE id = ?
        ''', [item.cantidad, isoNow, item.productoId]);

        if (updatedRows == 0) {
          throw Exception('No se encontró el producto ${item.productoId} para descontar stock.');
        }
      }

      // 3. Empaquetado del Evento Outbox (Patrón Outbox)
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
  // 2. CONSULTAS RÁPIDAS DE CAJA (LATENCIA CERO)
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

  Future<List<Product>> searchProductsByDescription(String query, {int limit = 15}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final db = await _dbHelper.database;

    final results = await db.query(
      'productos',
      where: 'descripcion LIKE ?',
      whereArgs: ['%$cleanQuery%'],
      orderBy: 'descripcion ASC',
      limit: limit,
    );

    return results.map((row) => Product.fromMap(row)).toList();
  }

  // ===========================================================================
  // 3. HISTORIAL Y DEVOLUCIONES (CAJ-07)
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
    final results = await db.query(
      'detalles_venta',
      where: 'venta_id = ?',
      whereArgs: [ventaId],
    );

    return results.map((map) => SaleDetailItem(
      id: map['id'] as String,
      productoId: map['producto_id'] as String,
      descripcion: 'Producto ID: ${map['producto_id']}',
      cantidad: (map['cantidad'] as num).toDouble(),
      precioHistorico: (map['precio_historico'] as num).toDouble(),
      totalLinea: (map['total_linea'] as num).toDouble(),
      costoHistorico: (map['costo_historico'] as num?)?.toDouble() ?? 0.0,
      descuentoLinea: (map['descuento_linea'] as num?)?.toDouble() ?? 0.0,
    )).toList();
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

      // 3. Recuperar partidas para reintegrar stock
      final detalles = await txn.query('detalles_venta', where: 'venta_id = ?', whereArgs: [ventaId]);
      
      for (final item in detalles) {
        final prodId = item['producto_id'] as String;
        final qty = (item['cantidad'] as num).toDouble();

        await txn.rawUpdate(
          'UPDATE productos SET stock_actual = stock_actual + ?, updated_at = ? WHERE id = ?',
          [qty, isoNow, prodId]
        );
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
}