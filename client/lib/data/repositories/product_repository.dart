import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import '../local/models.dart';
import 'dart:math';

class ProductRepository {
  final DatabaseHelper _dbHelper;

  ProductRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Inserta o actualiza un producto en el catálogo local y registra el evento Outbox
  Future<void> saveProduct(Product product, {bool isUpdate = false}) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      final isoNow = DateTime.now().toUtc().toIso8601String();
      final eventType = isUpdate ? 'PRODUCTO_MODIFICADO' : 'PRODUCTO_CREADO';

      // 1. Inserción o actualización en catálogo (Upsert)
      await txn.insert(
        'productos',
        {
          ...product.toMap(),
          'created_at': isoNow,
          'updated_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Empaquetado del Evento Outbox
      final outboxPayload = jsonEncode(product.toMap());

      // 3. Inserción en sync_queue con estado 'pending'
      await txn.insert(
        'sync_queue',
        {
          'id': '${product.id}_$isoNow', // ID compuesto para historial de cambios
          'event_type': eventType,
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

  /// Importa un catálogo masivo desde un CSV utilizando procesamiento por lotes (Batch)
  Future<int> importCatalogFromCSV(List<Map<String, dynamic>> parsedData) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    final isoNow = DateTime.now().toUtc().toIso8601String();
    int importedCount = 0;

    for (final row in parsedData) {
      final String id = _generateLocalUUID();
      
      // Aplicamos Upsert (Replace) basado en los constraints UNIQUE de schema.sql
      batch.insert(
        'productos',
        {
          'id': id,
          'codigo_barras': row['codigo']?.toString(),
          'sku': row['codigo']?.toString(),
          'descripcion': row['descripcion'].toString(),
          'precio_compra': (row['precio_compra'] as num).toDouble(),
          'precio_venta': (row['precio_venta'] as num).toDouble(),
          'porcentaje_impuesto': 0.0, // Valor por defecto o extraíble del CSV
          'departamento': row['departamento']?.toString() ?? 'General',
          'stock_actual': (row['stock'] as num).toDouble(),
          'es_a_granel': (row['stock'] as num).toDouble() % 1 != 0 ? 1 : 0,
          'created_at': isoNow,
          'updated_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      importedCount++;
    }

    // Se ejecuta toda la cola de forma atómica (sin emitir resultados individuales para no saturar memoria)
    await batch.commit(noResult: true);
    
    return importedCount;
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

