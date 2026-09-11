import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import '../local/models.dart';
import 'dart:async';

class InsufficientStockException implements Exception {
  final String productoId;
  final double disponible;
  final double solicitado;
  InsufficientStockException(this.productoId, this.disponible, this.solicitado);

  @override
  String toString() => 'Stock insuficiente para $productoId: Disp: $disponible, Req: $solicitado';
}

class SalesRepository {
  final DatabaseHelper _dbHelper;

  SalesRepository({DatabaseHelper? dbHelper}) 
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  // ===========================================================================
  // 1. TRANSACCIÓN ATÓMICA DE VENTA (ACID + OUTBOX PATTERN)
  // ===========================================================================
  /// Registra la venta, partidas, descuenta inventario (decimal) y emite el evento Outbox.
  /// En caso de error, la transacción revierte automáticamente todos los cambios.
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
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      // 2. Inserción de cada Partida y Reducción de Stock Decimal
      for (final item in sale.items) {
        // Inserción en detalles_venta
        await txn.insert(
          'detalles_venta',
          item.toMap(sale.ventaId),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        // Verificación y Descuento del Stock (Soporta granel)
        // Se ejecuta una actualización directa con decremento relativo
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

      // 4. Inserción en 'sync_queue' con estado 'pending'
      await txn.insert(
        'sync_queue',
        {
          'id': sale.ventaId, // Mismo ID de venta para asegurar idempotencia en backend
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

  /// Búsqueda exacta indexada por Código de Barras o SKU (Ideal para pistola lectora)
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

  /// Búsqueda predictiva e incremental por descripción para autocompletado en UI
  /// Limitada a 15 resultados para no saturar memoria ni render en hardware modesto.
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
}