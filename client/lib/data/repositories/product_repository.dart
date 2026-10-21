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
      if (term.toLowerCase().startsWith('molde:')) {
        final moldVal = term.substring(6).trim().toUpperCase();
        whereClauses.add('UPPER(codigo_equivalencia) = ?');
        whereArgs.add(moldVal);
      } else if (isDeepSearch) {
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

    // Mapear productos existentes para reutilizar id si ya existen por código o SKU
    final existingRows = await db.query('productos', columns: ['id', 'codigo_barras', 'sku']);
    final Map<String, String> existingIdsByCode = {};
    for (final r in existingRows) {
      final id = r['id'] as String;
      final cb = r['codigo_barras'] as String?;
      final sku = r['sku'] as String?;
      if (cb != null && cb.isNotEmpty) existingIdsByCode[cb] = id;
      if (sku != null && sku.isNotEmpty) existingIdsByCode[sku] = id;
    }

    // Registrar departamentos encontrados en el CSV
    final Set<String> deptos = {};
    for (final row in parsedData) {
      final d = row['departamento']?.toString().trim();
      if (d != null && d.isNotEmpty) {
        deptos.add(d);
      }
    }
    for (final dep in deptos) {
      final depId = 'DEP_${dep.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_')}';
      batch.insert(
        'departamentos',
        {
          'id': depId,
          'nombre': dep,
          'created_at': isoNow,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    for (final row in parsedData) {
      final String? codigo = row['codigo']?.toString() ?? row['codigo_barras']?.toString();
      final String? sku = row['sku']?.toString() ?? codigo;
      
      String id = row['id']?.toString() ?? '';
      if (id.isEmpty) {
        if (codigo != null && existingIdsByCode.containsKey(codigo)) {
          id = existingIdsByCode[codigo]!;
        } else if (sku != null && existingIdsByCode.containsKey(sku)) {
          id = existingIdsByCode[sku]!;
        } else {
          id = _generateLocalUUID();
        }
      }

      final String desc = row['descripcion']?.toString() ?? 'Producto Importado';
      final String nombre = row['nombre']?.toString() ?? desc;
      final double stockVal = (row['stock_actual'] as num?)?.toDouble() ?? 
                             (row['stock'] as num?)?.toDouble() ?? 0.0;
      final double stockMinVal = (row['stock_minimo'] as num?)?.toDouble() ?? 5.0;
      final int esGranelVal = (row['es_a_granel'] as int?) ?? (stockVal % 1 != 0 ? 1 : 0);

      batch.insert(
        'productos',
        {
          'id': id,
          'codigo_barras': codigo,
          'sku': sku,
          'nombre': nombre,
          'descripcion': desc,
          'marca': row['marca']?.toString() ?? 'Genérica',
          'codigo_equivalencia': row['codigo_equivalencia']?.toString(),
          'ubicacion': row['ubicacion']?.toString(),
          'precio_compra': (row['precio_compra'] as num?)?.toDouble() ?? 0.0,
          'precio_venta': (row['precio_venta'] as num?)?.toDouble() ?? 0.0,
          'precio_cerrajero': (row['precio_cerrajero'] as num?)?.toDouble(),
          'precio_taller': (row['precio_taller'] as num?)?.toDouble(),
          'porcentaje_impuesto': (row['porcentaje_impuesto'] as num?)?.toDouble() ?? 0.16,
          'departamento': row['departamento']?.toString() ?? 'General',
          'stock_actual': stockVal,
          'stock_minimo': stockMinVal,
          'es_a_granel': esGranelVal,
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

  /// Retorna listado de ubicaciones/gavetas únicas configuradas en el catálogo
  Future<List<String>> getDistinctLocations() async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery(
      "SELECT DISTINCT ubicacion FROM productos WHERE ubicacion IS NOT NULL AND TRIM(ubicacion) != '' ORDER BY ubicacion ASC;",
    );
    return results.map((r) => r['ubicacion'] as String).toList();
  }

  /// Registra una recepción de mercancía (Entrada masiva de compras)
  Future<void> recordGoodsReceipt(List<Map<String, dynamic>> items, {String usuarioId = 'cajero'}) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      for (final item in items) {
        final String prodId = item['producto_id'];
        final double qty = (item['cantidad'] as num).toDouble();
        final double cost = (item['precio_compra'] as num).toDouble();
        final double? newSalePrice = item['precio_venta'] != null ? (item['precio_venta'] as num).toDouble() : null;

        final rows = await txn.query('productos', where: 'id = ?', whereArgs: [prodId]);
        if (rows.isEmpty) continue;
        final currentProd = Product.fromMap(rows.first);
        final double currentStock = currentProd.stockActual;
        final double newStock = currentStock + qty;

        final updateMap = <String, dynamic>{
          'stock_actual': newStock,
          'precio_compra': cost,
          'updated_at': isoNow,
        };
        if (newSalePrice != null && newSalePrice > 0) {
          updateMap['precio_venta'] = newSalePrice;
        }

        await txn.update('productos', updateMap, where: 'id = ?', whereArgs: [prodId]);

        await _dbHelper.logInventoryMovement(
          db: txn,
          productoId: prodId,
          productoDesc: currentProd.nombre.isNotEmpty ? currentProd.nombre : currentProd.descripcion,
          tipo: 'ENTRADA',
          cantidad: qty,
          stockAnterior: currentStock,
          stockNuevo: newStock,
          usuarioId: usuarioId,
          departamento: currentProd.departamento,
          motivo: 'Recepción de pedido / Compra a proveedor',
        );

        final updatedProd = currentProd.copyWith(
          stockActual: newStock,
          precioCompra: cost,
          precioVenta: newSalePrice ?? currentProd.precioVenta,
        );
        await txn.insert('sync_queue', {
          'id': 'RECEIPT_${prodId}_${DateTime.now().millisecondsSinceEpoch}',
          'event_type': 'PRODUCTO_MODIFICADO',
          'payload': jsonEncode(updatedProd.toMap()),
          'sync_status': 'pending',
          'created_at': isoNow,
        });
      }
    });
  }

  /// Entrada rápida de stock desde el Inspector
  Future<void> quickStockEntry(String productoId, double qty, {String usuarioId = 'cajero', String? motivo}) async {
    if (qty <= 0) return;
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('productos', where: 'id = ?', whereArgs: [productoId]);
      if (rows.isEmpty) return;
      final currentProd = Product.fromMap(rows.first);
      final double currentStock = currentProd.stockActual;
      final double newStock = currentStock + qty;

      await txn.update('productos', {'stock_actual': newStock, 'updated_at': isoNow}, where: 'id = ?', whereArgs: [productoId]);

      await _dbHelper.logInventoryMovement(
        db: txn,
        productoId: productoId,
        productoDesc: currentProd.nombre.isNotEmpty ? currentProd.nombre : currentProd.descripcion,
        tipo: 'ENTRADA',
        cantidad: qty,
        stockAnterior: currentStock,
        stockNuevo: newStock,
        usuarioId: usuarioId,
        departamento: currentProd.departamento,
        motivo: motivo ?? 'Entrada rápida de stock',
      );

      final updatedProd = currentProd.copyWith(stockActual: newStock);
      await txn.insert('sync_queue', {
        'id': 'QUICK_${productoId}_${DateTime.now().millisecondsSinceEpoch}',
        'event_type': 'PRODUCTO_MODIFICADO',
        'payload': jsonEncode(updatedProd.toMap()),
        'sync_status': 'pending',
        'created_at': isoNow,
      });
    });
  }

  /// Aplica ajustes de auditoría física por gaveta o departamento
  Future<int> applyAuditAdjustments(List<Map<String, dynamic>> adjustments, {String usuarioId = 'cajero'}) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();
    int adjustedCount = 0;

    await db.transaction((txn) async {
      for (final adj in adjustments) {
        final String prodId = adj['producto_id'];
        final double physicalCount = (adj['conteo_fisico'] as num).toDouble();

        final rows = await txn.query('productos', where: 'id = ?', whereArgs: [prodId]);
        if (rows.isEmpty) continue;
        final currentProd = Product.fromMap(rows.first);
        final double currentStock = currentProd.stockActual;
        final double diff = physicalCount - currentStock;

        if (diff == 0) continue;

        await txn.update('productos', {'stock_actual': physicalCount, 'updated_at': isoNow}, where: 'id = ?', whereArgs: [prodId]);

        await _dbHelper.logInventoryMovement(
          db: txn,
          productoId: prodId,
          productoDesc: currentProd.nombre.isNotEmpty ? currentProd.nombre : currentProd.descripcion,
          tipo: 'AJUSTE',
          cantidad: diff.abs(),
          stockAnterior: currentStock,
          stockNuevo: physicalCount,
          usuarioId: usuarioId,
          departamento: currentProd.departamento,
          motivo: adj['motivo'] ?? 'Ajuste de inventario físico por gaveta (${currentProd.ubicacion ?? "Sin Ubicación"})',
        );

        await txn.insert('sync_queue', {
          'id': 'AUDIT_${prodId}_${DateTime.now().millisecondsSinceEpoch}',
          'event_type': 'AJUSTE_INVENTARIO',
          'payload': jsonEncode({
            'ajuste_id': 'ADJ_${DateTime.now().millisecondsSinceEpoch}',
            'producto_id': prodId,
            'stock_teorico': currentStock,
            'stock_fisico': physicalCount,
            'diferencia': diff,
            'motivo': 'Auditoría por gaveta',
            'autorizado_por': usuarioId,
            'fecha_ajuste': isoNow,
          }),
          'sync_status': 'pending',
          'created_at': isoNow,
        });

        adjustedCount++;
      }
    });

    return adjustedCount;
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
