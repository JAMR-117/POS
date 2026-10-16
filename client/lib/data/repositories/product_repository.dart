import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import '../local/models.dart';

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
          'id': '${product.id}_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Consulta todos los productos locales
  Future<List<Product>> getAllProducts() async {
    final db = await _dbHelper.database;
    final results = await db.query('productos', orderBy: 'nombre ASC');
    return results.map((row) => Product.fromMap(row)).toList();
  }

  /// Retorna exclusivamente los productos físicos (no servicios) para usar como insumos vinculados
  Future<List<Product>> getPhysicalProducts() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'productos',
      where: 'es_servicio = 0 AND id != ?',
      whereArgs: ['ART-COMUN'],
      orderBy: 'nombre ASC',
    );
    return results.map((row) => Product.fromMap(row)).toList();
  }

  /// Búsqueda y filtrado exhaustivo 100% Offline para InventoryScreen
  Future<List<Product>> searchProducts({
    String query = '',
    String? departamento,
    String? marca,
    bool? soloServicios,
    bool? soloFisicos,
    String sortBy = 'nombre_asc',
  }) async {
    final db = await _dbHelper.database;
    final cleanQuery = query.trim();
    final bool isDeepSearch = cleanQuery.startsWith('%');
    final String term = isDeepSearch ? cleanQuery.substring(1).trim() : cleanQuery;

    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (term.isNotEmpty) {
      if (isDeepSearch) {
        whereClauses.add(
          '(descripcion LIKE ? OR nombre LIKE ? OR sku LIKE ? OR marca LIKE ? OR codigo_barras LIKE ? OR codigo_equivalencia LIKE ? OR ubicacion LIKE ?)',
        );
        final pattern = '%$term%';
        whereArgs.addAll([pattern, pattern, pattern, pattern, pattern, pattern, pattern]);
      } else {
        whereClauses.add(
          '(nombre LIKE ? OR sku LIKE ? OR codigo_barras LIKE ? OR marca LIKE ? OR codigo_equivalencia LIKE ?)',
        );
        final pattern = '%$term%';
        whereArgs.addAll([pattern, pattern, pattern, pattern, pattern]);
      }
    }

    if (departamento != null && departamento.isNotEmpty && departamento != 'Todos') {
      whereClauses.add('departamento = ?');
      whereArgs.add(departamento);
    }

    if (marca != null && marca.isNotEmpty && marca != 'Todas') {
      whereClauses.add('marca = ?');
      whereArgs.add(marca);
    }

    if (soloServicios == true) {
      whereClauses.add('es_servicio = 1');
    } else if (soloFisicos == true) {
      whereClauses.add('es_servicio = 0');
    }

    String orderBySql;
    switch (sortBy) {
      case 'stock_asc':
        orderBySql = 'stock_actual ASC';
        break;
      case 'stock_desc':
        orderBySql = 'stock_actual DESC';
        break;
      case 'precio_asc':
        orderBySql = 'precio_venta ASC';
        break;
      case 'precio_desc':
        orderBySql = 'precio_venta DESC';
        break;
      case 'marca_asc':
        orderBySql = 'marca ASC, nombre ASC';
        break;
      case 'nombre_desc':
        orderBySql = 'nombre DESC';
        break;
      case 'nombre_asc':
      default:
        orderBySql = 'nombre ASC';
        break;
    }

    final results = await db.query(
      'productos',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereClauses.isEmpty ? null : whereArgs,
      orderBy: orderBySql,
    );

    return results.map((row) => Product.fromMap(row)).toList();
  }

  /// Elimina un producto del catálogo local y encola evento de eliminación
  Future<void> deleteProduct(String id) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete('productos', where: 'id = ?', whereArgs: [id]);
      await txn.insert(
        'sync_queue',
        {
          'id': 'DEL_${id}_${DateTime.now().millisecondsSinceEpoch}',
          'event_type': 'PRODUCTO_ELIMINADO',
          'payload': jsonEncode({'id': id, 'timestamp': isoNow}),
          'sync_status': 'pending',
          'created_at': isoNow,
        },
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
      final String id = row['id']?.toString() ?? _generateLocalUUID();
      final String desc = row['descripcion']?.toString() ?? 'Producto Importado';
      final String nombre = row['nombre']?.toString() ?? desc;

      batch.insert(
        'productos',
        {
          'id': id,
          'codigo_barras': row['codigo']?.toString(),
          'sku': row['codigo']?.toString(),
          'nombre': nombre,
          'descripcion': desc,
          'marca': row['marca']?.toString() ?? 'Genérica',
          'codigo_equivalencia': row['codigo_equivalencia']?.toString(),
          'ubicacion': row['ubicacion']?.toString(),
          'precio_compra': (row['precio_compra'] as num?)?.toDouble() ?? 0.0,
          'precio_venta': (row['precio_venta'] as num?)?.toDouble() ?? 0.0,
          'porcentaje_impuesto': (row['porcentaje_impuesto'] as num?)?.toDouble() ?? 0.16,
          'departamento': row['departamento']?.toString() ?? 'General',
          'stock_actual': (row['stock'] as num?)?.toDouble() ?? 0.0,
          'es_a_granel': ((row['stock'] as num?)?.toDouble() ?? 0.0) % 1 != 0 ? 1 : 0,
          'cantidad_mayoreo': (row['cantidad_mayoreo'] as num?)?.toDouble(),
          'precio_mayoreo': (row['precio_mayoreo'] as num?)?.toDouble(),
          'es_servicio': (row['es_servicio'] as int?) ?? 0,
          'insumo_vinculado_id': row['insumo_vinculado_id']?.toString(),
          'cantidad_insumo': (row['cantidad_insumo'] as num?)?.toDouble() ?? 1.0,
          'created_at': isoNow,
          'updated_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      importedCount++;
    }

    await batch.commit(noResult: true);
    return importedCount;
  }

  Future<List<String>> getDepartmentNames() async {
    final db = await _dbHelper.database;
    final results = await db.query('departamentos', columns: ['nombre'], orderBy: 'nombre ASC');
    return results.map((r) => r['nombre'] as String).toList();
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
