import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';

class InventoryRepository {
  final DatabaseHelper _dbHelper;

  InventoryRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Ejecuta el ajuste de inventario físico y registra el evento Outbox (ACID)
  Future<void> adjustStock({
    required String productoId,
    required double stockFisico,
    required String motivo,
    required String adminId,
  }) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // 1. Obtener el stock teórico actual
      final results = await txn.query(
        'productos',
        columns: ['stock_actual'],
        where: 'id = ?',
        whereArgs: [productoId],
        limit: 1,
      );

      if (results.isEmpty) throw Exception('Producto no encontrado en la base local.');
      final stockTeorico = (results.first['stock_actual'] as num).toDouble();
      final diferencia = stockFisico - stockTeorico;

      // 2. Actualizar el stock en el catálogo
      await txn.update(
        'productos',
        {
          'stock_actual': stockFisico,
          'updated_at': isoNow,
        },
        where: 'id = ?',
        whereArgs: [productoId],
      );

      // 3. Generar evento de auditoría en sync_queue (Patrón Outbox)
      final eventId = 'ADJ_${productoId}_${DateTime.now().millisecondsSinceEpoch}';
      final outboxPayload = jsonEncode({
        'ajuste_id': eventId,
        'producto_id': productoId,
        'stock_teorico': stockTeorico,
        'stock_fisico': stockFisico,
        'diferencia': diferencia,
        'motivo': motivo,
        'autorizado_por': adminId,
        'fecha_ajuste': isoNow,
      });

      await txn.insert(
        'sync_queue',
        {
          'id': eventId,
          'event_type': 'AJUSTE_INVENTARIO',
          'payload': outboxPayload,
          'sync_status': 'pending',
          'created_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }
}