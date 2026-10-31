import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import '../../core/department_theme.dart';
import 'database_seeder.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static int _movSeq = 0;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// Configura pragmas de bajo nivel y baja latencia para hardware limitado
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    if (!kIsWeb) {
      await db.execute('PRAGMA journal_mode = WAL;');
      await db.execute('PRAGMA synchronous = NORMAL;');
    }
  }

  Future<void> _onOpen(Database db) async {
    // Garantiza que los registros semilla permanentes siempre existan
    await DatabaseSeeder.seed(db);
    // Auto-bootstrap silencioso de catálogo migrado y clientes
    await _autoBootstrapData(db);
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Creación secuencial de tablas principales
    final List<String> tables = [
      '''CREATE TABLE IF NOT EXISTS cortes_caja (
          id TEXT PRIMARY KEY NOT NULL,
          folio_corte INTEGER,
          usuario_id TEXT NOT NULL,
          monto_inicial REAL NOT NULL DEFAULT 0.0,
          monto_ventas_efectivo REAL NOT NULL DEFAULT 0.0,
          monto_ventas_tarjeta REAL NOT NULL DEFAULT 0.0,
          monto_ventas_otros REAL NOT NULL DEFAULT 0.0,
          monto_retiros REAL NOT NULL DEFAULT 0.0,
          tipo_corte TEXT NOT NULL CHECK (tipo_corte IN ('X', 'Z')),
          discrepancia REAL DEFAULT 0.0,
          fecha_apertura TEXT NOT NULL,
          fecha_cierre TEXT,
          estado TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado'))
      );''',
      '''CREATE TABLE IF NOT EXISTS departamentos (
          id TEXT PRIMARY KEY NOT NULL,
          nombre TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL
      );''',
      '''CREATE TABLE IF NOT EXISTS productos (
          id TEXT PRIMARY KEY NOT NULL,
          codigo_barras TEXT UNIQUE,
          sku TEXT UNIQUE,
          nombre TEXT NOT NULL,
          descripcion TEXT NOT NULL,
          marca TEXT,
          codigo_equivalencia TEXT,
          ubicacion TEXT,
          precio_compra REAL NOT NULL DEFAULT 0.0,
          precio_venta REAL NOT NULL,
          precio_cerrajero REAL,
          precio_taller REAL,
          porcentaje_impuesto REAL NOT NULL DEFAULT 0.0,
          departamento TEXT DEFAULT 'Residencial',
          departamentos_aplicables TEXT DEFAULT 'Todos',
          stock_actual REAL NOT NULL DEFAULT 0.0,
          stock_minimo REAL NOT NULL DEFAULT 5.0,
          es_a_granel INTEGER NOT NULL DEFAULT 0 CHECK (es_a_granel IN (0, 1)),
          cantidad_mayoreo REAL,
          precio_mayoreo REAL,
          es_servicio INTEGER NOT NULL DEFAULT 0 CHECK (es_servicio IN (0, 1)),
          insumo_vinculado_id TEXT,
          cantidad_insumo REAL NOT NULL DEFAULT 1.0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (insumo_vinculado_id) REFERENCES productos(id) ON DELETE SET NULL
      );''',
      '''CREATE TABLE IF NOT EXISTS ventas (
          id TEXT PRIMARY KEY NOT NULL,
          corte_caja_id TEXT NOT NULL,
          cliente_id TEXT DEFAULT 'PUBLICO-GRAL',
          cliente_nombre TEXT DEFAULT 'Público en General',
          folio_ticket TEXT,
          subtotal REAL NOT NULL,
          descuento_total REAL NOT NULL DEFAULT 0.0,
          impuestos_total REAL NOT NULL DEFAULT 0.0,
          total REAL NOT NULL,
          pagos_desglose TEXT NOT NULL,
          fecha_venta TEXT NOT NULL,
          estatus TEXT NOT NULL DEFAULT 'completado' CHECK (estatus IN ('completado', 'cancelado')),
          FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
      );''',
      '''CREATE TABLE IF NOT EXISTS detalles_venta (
          id TEXT PRIMARY KEY NOT NULL,
          venta_id TEXT NOT NULL,
          producto_id TEXT NOT NULL,
          cantidad REAL NOT NULL,
          precio_historico REAL NOT NULL,
          costo_historico REAL NOT NULL DEFAULT 0.0,
          descuento_linea REAL NOT NULL DEFAULT 0.0,
          total_linea REAL NOT NULL,
          insumo_utilizado_id TEXT,
          cantidad_insumo_consumida REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
          FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT
      );''',
      '''CREATE TABLE IF NOT EXISTS usuarios (
          id TEXT PRIMARY KEY NOT NULL,
          nombre TEXT NOT NULL,
          pin_acceso TEXT NOT NULL UNIQUE,
          rol TEXT NOT NULL CHECK (rol IN ('admin', 'cajero')),
          permisos TEXT,
          activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1))
      );''',
      '''CREATE TABLE IF NOT EXISTS clientes (
          id TEXT PRIMARY KEY NOT NULL,
          nombre TEXT NOT NULL,
          rfc_o_dni TEXT,
          regimen_fiscal TEXT,
          uso_cfdi TEXT,
          codigo_postal TEXT,
          correo TEXT,
          telefono TEXT,
          direccion TEXT,
          limite_credito REAL NOT NULL DEFAULT 0.0,
          saldo_deudor REAL NOT NULL DEFAULT 0.0,
          tarifa_preferencial TEXT NOT NULL DEFAULT 'Público',
          activo INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL
      );''',
      '''CREATE TABLE IF NOT EXISTS abonos_credito (
          id TEXT PRIMARY KEY NOT NULL,
          cliente_id TEXT NOT NULL,
          corte_caja_id TEXT NOT NULL,
          monto REAL NOT NULL,
          fecha TEXT NOT NULL,
          FOREIGN KEY (cliente_id) REFERENCES clientes(id)
      );''',
      '''CREATE TABLE IF NOT EXISTS movimientos_caja (
          id TEXT PRIMARY KEY NOT NULL,
          corte_caja_id TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('entrada', 'salida')),
          monto REAL NOT NULL,
          concepto TEXT NOT NULL,
          fecha TEXT NOT NULL,
          FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
      );''',
      '''CREATE TABLE IF NOT EXISTS movimientos_inventario (
          id TEXT PRIMARY KEY NOT NULL,
          producto_id TEXT NOT NULL,
          producto_desc TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION')),
          cantidad REAL NOT NULL,
          stock_anterior REAL NOT NULL,
          stock_nuevo REAL NOT NULL,
          usuario_id TEXT NOT NULL,
          departamento TEXT,
          motivo TEXT,
          fecha TEXT NOT NULL,
          created_at TEXT NOT NULL
      );''',
      '''CREATE TABLE IF NOT EXISTS sync_queue (
          id TEXT PRIMARY KEY NOT NULL,
          event_type TEXT NOT NULL,
          payload TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
          retry_count INTEGER NOT NULL DEFAULT 0,
          error_code TEXT,
          created_at TEXT NOT NULL,
          synced_at TEXT
      );''',
      '''CREATE TABLE IF NOT EXISTS app_metadata (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
      );''',
      '''CREATE TABLE IF NOT EXISTS configuracion_negocio (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
      );'''
    ];

    for (final tableSql in tables) {
      await db.execute(tableSql);
    }

    // 2. Creación de índices
    final List<String> indices = [
      'CREATE INDEX IF NOT EXISTS idx_productos_codigo_barras ON productos(codigo_barras);',
      'CREATE INDEX IF NOT EXISTS idx_productos_sku ON productos(sku);',
      'CREATE INDEX IF NOT EXISTS idx_productos_equivalencia ON productos(codigo_equivalencia);',
      'CREATE INDEX IF NOT EXISTS idx_productos_nombre ON productos(nombre);',
      'CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos(marca);',
      'CREATE INDEX IF NOT EXISTS idx_mov_inv_prod ON movimientos_inventario(producto_id);',
      'CREATE INDEX IF NOT EXISTS idx_mov_inv_fecha ON movimientos_inventario(fecha);',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created ON sync_queue(sync_status, created_at);',
      'CREATE INDEX IF NOT EXISTS idx_ventas_corte_id ON ventas(corte_caja_id);',
      'CREATE INDEX IF NOT EXISTS idx_ventas_cliente_id ON ventas(cliente_id);',
      'CREATE INDEX IF NOT EXISTS idx_detalles_venta_venta_id ON detalles_venta(venta_id);',
      'CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes(nombre);',
      'CREATE INDEX IF NOT EXISTS idx_movimientos_corte_id ON movimientos_caja(corte_caja_id);'
    ];

    for (final indexSql in indices) {
      await db.execute(indexSql);
    }

    await DatabaseSeeder.seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migración acumulativa segura para cualquier versión anterior
    final tableInfoProd = await db.rawQuery('PRAGMA table_info(productos);');
    final prodCols = tableInfoProd.map((col) => col['name'] as String).toSet();

    if (!prodCols.contains('nombre')) {
      await db.execute("ALTER TABLE productos ADD COLUMN nombre TEXT NOT NULL DEFAULT '';");
      await db.execute("UPDATE productos SET nombre = descripcion WHERE nombre = '';");
    }
    if (!prodCols.contains('marca')) await db.execute("ALTER TABLE productos ADD COLUMN marca TEXT;");
    if (!prodCols.contains('codigo_equivalencia')) await db.execute("ALTER TABLE productos ADD COLUMN codigo_equivalencia TEXT;");
    if (!prodCols.contains('ubicacion')) await db.execute("ALTER TABLE productos ADD COLUMN ubicacion TEXT;");
    if (!prodCols.contains('es_servicio')) await db.execute("ALTER TABLE productos ADD COLUMN es_servicio INTEGER NOT NULL DEFAULT 0;");
    if (!prodCols.contains('insumo_vinculado_id')) await db.execute("ALTER TABLE productos ADD COLUMN insumo_vinculado_id TEXT;");
    if (!prodCols.contains('cantidad_insumo')) await db.execute("ALTER TABLE productos ADD COLUMN cantidad_insumo REAL NOT NULL DEFAULT 1.0;");
    if (!prodCols.contains('cantidad_mayoreo')) await db.execute("ALTER TABLE productos ADD COLUMN cantidad_mayoreo REAL;");
    if (!prodCols.contains('precio_mayoreo')) await db.execute("ALTER TABLE productos ADD COLUMN precio_mayoreo REAL;");
    
    // Nivel 2 y 3 de precios y stock mínimo (v3) + Dynamic Runtime BOM (v4)
    if (!prodCols.contains('precio_cerrajero')) await db.execute("ALTER TABLE productos ADD COLUMN precio_cerrajero REAL;");
    if (!prodCols.contains('precio_taller')) await db.execute("ALTER TABLE productos ADD COLUMN precio_taller REAL;");
    if (!prodCols.contains('stock_minimo')) await db.execute("ALTER TABLE productos ADD COLUMN stock_minimo REAL NOT NULL DEFAULT 5.0;");
    if (!prodCols.contains('departamentos_aplicables')) {
      await db.execute("ALTER TABLE productos ADD COLUMN departamentos_aplicables TEXT DEFAULT 'Todos';");
    }

    // Detalles de venta: vínculo dinámico de insumo en caja (v4)
    final tableInfoDet = await db.rawQuery('PRAGMA table_info(detalles_venta);');
    final detCols = tableInfoDet.map((col) => col['name'] as String).toSet();
    if (!detCols.contains('insumo_utilizado_id')) {
      await db.execute("ALTER TABLE detalles_venta ADD COLUMN insumo_utilizado_id TEXT;");
    }
    if (!detCols.contains('cantidad_insumo_consumida')) {
      await db.execute("ALTER TABLE detalles_venta ADD COLUMN cantidad_insumo_consumida REAL NOT NULL DEFAULT 0.0;");
    }

    // Clientes extendidos
    final tableInfoCli = await db.rawQuery('PRAGMA table_info(clientes);');
    final cliCols = tableInfoCli.map((col) => col['name'] as String).toSet();
    if (!cliCols.contains('regimen_fiscal')) await db.execute("ALTER TABLE clientes ADD COLUMN regimen_fiscal TEXT;");
    if (!cliCols.contains('uso_cfdi')) await db.execute("ALTER TABLE clientes ADD COLUMN uso_cfdi TEXT;");
    if (!cliCols.contains('codigo_postal')) await db.execute("ALTER TABLE clientes ADD COLUMN codigo_postal TEXT;");
    if (!cliCols.contains('correo')) await db.execute("ALTER TABLE clientes ADD COLUMN correo TEXT;");
    if (!cliCols.contains('direccion')) await db.execute("ALTER TABLE clientes ADD COLUMN direccion TEXT;");
    if (!cliCols.contains('tarifa_preferencial')) await db.execute("ALTER TABLE clientes ADD COLUMN tarifa_preferencial TEXT NOT NULL DEFAULT 'Público';");

    // Usuarios: permisos
    final tableInfoUsr = await db.rawQuery('PRAGMA table_info(usuarios);');
    final usrCols = tableInfoUsr.map((col) => col['name'] as String).toSet();
    if (!usrCols.contains('permisos')) await db.execute("ALTER TABLE usuarios ADD COLUMN permisos TEXT;");

    // Ventas: cliente_id y cliente_nombre para trazabilidad de crédito y estado de cuenta (v5)
    final tableInfoVentas = await db.rawQuery('PRAGMA table_info(ventas);');
    final ventasCols = tableInfoVentas.map((col) => col['name'] as String).toSet();
    if (!ventasCols.contains('cliente_id')) {
      await db.execute("ALTER TABLE ventas ADD COLUMN cliente_id TEXT DEFAULT 'PUBLICO-GRAL';");
    }
    if (!ventasCols.contains('cliente_nombre')) {
      await db.execute("ALTER TABLE ventas ADD COLUMN cliente_nombre TEXT DEFAULT 'Público en General';");
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_cliente_id ON ventas(cliente_id);');

    // Tablas nuevas
    await db.execute('''CREATE TABLE IF NOT EXISTS departamentos (
        id TEXT PRIMARY KEY NOT NULL,
        nombre TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
    );''');

    await db.execute('''CREATE TABLE IF NOT EXISTS movimientos_inventario (
        id TEXT PRIMARY KEY NOT NULL,
        producto_id TEXT NOT NULL,
        producto_desc TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION')),
        cantidad REAL NOT NULL,
        stock_anterior REAL NOT NULL,
        stock_nuevo REAL NOT NULL,
        usuario_id TEXT NOT NULL,
        departamento TEXT,
        motivo TEXT,
        fecha TEXT NOT NULL,
        created_at TEXT NOT NULL
    );''');

    await db.execute('''CREATE TABLE IF NOT EXISTS configuracion_negocio (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_mov_inv_prod ON movimientos_inventario(producto_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_mov_inv_fecha ON movimientos_inventario(fecha);');
  }

  /// Auto-importación silenciosa en segundo plano si el catálogo o clientes están vacíos
  Future<void> _autoBootstrapData(Database db) async {
    try {
      // 1. Columnas de analítica, métricas predictivas y Dynamic Runtime BOM
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN ventas_ultimos_30dias REAL DEFAULT 0.0;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN total_unidades_vendidas REAL DEFAULT 0.0;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE productos ADD COLUMN ultima_venta_at TEXT;');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE productos ADD COLUMN departamentos_aplicables TEXT DEFAULT 'Todos';");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE detalles_venta ADD COLUMN insumo_utilizado_id TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE detalles_venta ADD COLUMN cantidad_insumo_consumida REAL NOT NULL DEFAULT 0.0;');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE ventas ADD COLUMN cliente_id TEXT DEFAULT 'PUBLICO-GRAL';");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE ventas ADD COLUMN cliente_nombre TEXT DEFAULT 'Público en General';");
      } catch (_) {}

      // 2. Auto-bootstrap / consolidación limpia v5 desde assets/catalogo_migrado_pos.csv
      final pCount = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM productos WHERE es_servicio = 0 AND id != 'ART-COMUN';",
      )) ?? 0;

      final v5MetaRows = await db.query('app_metadata', where: 'key = ?', whereArgs: ['catalog_v5_cleaned'], limit: 1);
      final bool alreadyCleanedV5 = v5MetaRows.isNotEmpty && v5MetaRows.first['value'] == 'true';

      if (pCount == 0 || !alreadyCleanedV5) {
        final csvString = await rootBundle.loadString('assets/catalogo_migrado_pos.csv');
        if (csvString.isNotEmpty) {
          final normalizedCsv = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
          final rows = const CsvToListConverter(eol: '\n', fieldDelimiter: ',', shouldParseNumbers: false).convert(normalizedCsv);
          if (rows.length > 1) {
            final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
            final colCodigo = header.indexOf('codigo');
            final colSku = header.indexOf('sku');
            final colNombre = header.indexOf('nombre');
            final colDesc = header.indexOf('descripcion');
            final colMarca = header.indexOf('marca');
            final colMolde = header.indexOf('codigo_equivalencia');
            final colUbi = header.indexOf('ubicacion');
            final colDepto = header.indexOf('departamento');
            final colDeptosApl = header.indexOf('departamentos_aplicables');
            final colPC = header.indexOf('precio_compra');
            final colPV = header.indexOf('precio_venta');
            final colPCerrajero = header.indexOf('precio_cerrajero');
            final colPTaller = header.indexOf('precio_taller');
            final colPMayoreo = header.indexOf('precio_mayoreo');
            final colCantMayoreo = header.indexOf('cantidad_mayoreo');
            final colStock = header.indexOf('stock_actual');
            final colStockMin = header.indexOf('stock_minimo');
            final colGranel = header.indexOf('es_a_granel');
            final colServicio = header.indexOf('es_servicio');
            final colV30d = header.indexOf('ventas_ultimos_30dias');
            final colTotVendidas = header.indexOf('total_unidades_vendidas');
            final colUltVenta = header.indexOf('ultima_venta_at');

            final isoNow = DateTime.now().toUtc().toIso8601String();
            final Set<String> validCatalogIds = {'ART-COMUN'};

            // Estandarizar tabla de departamentos a las 9 categorías limpias
            await db.delete('departamentos');
            for (final d in kAllStandardDepartments) {
              final depId = 'dep-${d.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
              await db.insert(
                'departamentos',
                {'id': depId, 'nombre': d, 'created_at': isoNow},
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }

            final batch = db.batch();
            for (int i = 1; i < rows.length; i++) {
              final r = rows[i];
              if (r.isEmpty) continue;
              final cod = colCodigo != -1 && r.length > colCodigo ? r[colCodigo]?.toString().trim() : '';
              final sku = colSku != -1 && r.length > colSku ? r[colSku]?.toString().trim() : cod;
              if (cod == null || cod.isEmpty) continue;

              final id = cod;
              validCatalogIds.add(id);
              final desc = colDesc != -1 && r.length > colDesc ? r[colDesc]?.toString().trim() : 'Producto';
              final nombre = colNombre != -1 && r.length > colNombre ? r[colNombre]?.toString().trim() : desc;
              final rawDeptosApl = colDeptosApl != -1 && r.length > colDeptosApl ? r[colDeptosApl]?.toString().trim() : '';

              batch.insert(
                'productos',
                {
                  'id': id,
                  'codigo_barras': cod,
                  'sku': sku,
                  'nombre': (nombre != null && nombre.isNotEmpty) ? nombre : desc,
                  'descripcion': (desc != null && desc.isNotEmpty) ? desc : nombre,
                  'marca': colMarca != -1 && r.length > colMarca ? r[colMarca]?.toString() : 'Genérica',
                  'codigo_equivalencia': colMolde != -1 && r.length > colMolde && r[colMolde].toString().trim().isNotEmpty ? r[colMolde].toString().trim() : null,
                  'ubicacion': colUbi != -1 && r.length > colUbi && r[colUbi].toString().trim().isNotEmpty ? r[colUbi].toString().trim() : null,
                  'departamento': colDepto != -1 && r.length > colDepto && r[colDepto].toString().trim().isNotEmpty ? r[colDepto].toString().trim() : 'Residencial',
                  'departamentos_aplicables': (rawDeptosApl != null && rawDeptosApl.isNotEmpty) ? rawDeptosApl : 'Todos',
                  'precio_compra': colPC != -1 && r.length > colPC ? (num.tryParse(r[colPC].toString())?.toDouble() ?? 0.0) : 0.0,
                  'precio_venta': colPV != -1 && r.length > colPV ? (num.tryParse(r[colPV].toString())?.toDouble() ?? 0.0) : 0.0,
                  'precio_cerrajero': colPCerrajero != -1 && r.length > colPCerrajero ? num.tryParse(r[colPCerrajero].toString())?.toDouble() : null,
                  'precio_taller': colPTaller != -1 && r.length > colPTaller ? num.tryParse(r[colPTaller].toString())?.toDouble() : null,
                  'precio_mayoreo': colPMayoreo != -1 && r.length > colPMayoreo ? num.tryParse(r[colPMayoreo].toString())?.toDouble() : null,
                  'cantidad_mayoreo': colCantMayoreo != -1 && r.length > colCantMayoreo ? num.tryParse(r[colCantMayoreo].toString())?.toDouble() : null,
                  'stock_actual': colStock != -1 && r.length > colStock ? (num.tryParse(r[colStock].toString())?.toDouble() ?? 0.0) : 0.0,
                  'stock_minimo': colStockMin != -1 && r.length > colStockMin ? (num.tryParse(r[colStockMin].toString())?.toDouble() ?? 5.0) : 5.0,
                  'es_a_granel': colGranel != -1 && r.length > colGranel ? (int.tryParse(r[colGranel].toString()) ?? 0) : 0,
                  'es_servicio': colServicio != -1 && r.length > colServicio ? (int.tryParse(r[colServicio].toString()) ?? 0) : 0,
                  'insumo_vinculado_id': null,
                  'cantidad_insumo': 1.0,
                  'ventas_ultimos_30dias': colV30d != -1 && r.length > colV30d ? (num.tryParse(r[colV30d].toString())?.toDouble() ?? 0.0) : 0.0,
                  'total_unidades_vendidas': colTotVendidas != -1 && r.length > colTotVendidas ? (num.tryParse(r[colTotVendidas].toString())?.toDouble() ?? 0.0) : 0.0,
                  'ultima_venta_at': colUltVenta != -1 && r.length > colUltVenta && r[colUltVenta].toString().trim().isNotEmpty ? r[colUltVenta].toString().trim() : null,
                  'created_at': isoNow,
                  'updated_at': isoNow,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);

            // Limpiar servicios individuales obsoletos y duplicados viejos no referenciados en ventas históricas
            final existingProds = await db.query('productos', columns: ['id']);
            final usedRows = await db.rawQuery('SELECT DISTINCT producto_id FROM detalles_venta;');
            final Set<String> usedIds = usedRows
                .map((r) => r['producto_id']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toSet();

            final cleanBatch = db.batch();
            for (final ep in existingProds) {
              final eid = ep['id'] as String;
              if (!validCatalogIds.contains(eid) && !usedIds.contains(eid)) {
                cleanBatch.delete('productos', where: 'id = ?', whereArgs: [eid]);
              }
            }
            await cleanBatch.commit(noResult: true);

            await db.insert(
              'app_metadata',
              {'key': 'catalog_v5_cleaned', 'value': 'true', 'updated_at': isoNow},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      // 3. Auto-bootstrap de clientes desde assets
      final cCount = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM clientes WHERE id NOT IN ('PUBLICO-GRAL', 'cli-cerrajero-juan', 'cli-taller-automotriz');",
      )) ?? 0;

      if (cCount == 0) {
        final csvString = await rootBundle.loadString('assets/clientes_migrados_pos.csv');
        if (csvString.isNotEmpty) {
          final rows = const CsvToListConverter(eol: '\n', fieldDelimiter: ',', shouldParseNumbers: false).convert(csvString);
          if (rows.length > 1) {
            final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
            final colId = header.indexOf('id');
            final colNombre = header.indexOf('nombre');
            final colTel = header.indexOf('telefono');
            final colEmail = header.indexOf('email');
            final colDir = header.indexOf('direccion');
            final colLimite = header.indexOf('limite_credito');
            final colSaldo = header.indexOf('saldo_actual');

            final isoNow = DateTime.now().toUtc().toIso8601String();
            final batch = db.batch();

            for (int i = 1; i < rows.length; i++) {
              final r = rows[i];
              if (r.isEmpty) continue;
              final cid = colId != -1 && r.length > colId ? r[colId]?.toString().trim() : '';
              final nom = colNombre != -1 && r.length > colNombre ? r[colNombre]?.toString().trim() : '';
              if (cid == null || cid.isEmpty || nom == null || nom.isEmpty) continue;

              batch.insert(
                'clientes',
                {
                  'id': cid,
                  'nombre': nom,
                  'telefono': colTel != -1 && r.length > colTel ? r[colTel]?.toString() : null,
                  'correo': colEmail != -1 && r.length > colEmail ? r[colEmail]?.toString() : null,
                  'direccion': colDir != -1 && r.length > colDir ? r[colDir]?.toString() : null,
                  'limite_credito': colLimite != -1 && r.length > colLimite ? (num.tryParse(r[colLimite].toString())?.toDouble() ?? 0.0) : 0.0,
                  'saldo_deudor': colSaldo != -1 && r.length > colSaldo ? (num.tryParse(r[colSaldo].toString())?.toDouble() ?? 0.0) : 0.0,
                  'activo': 1,
                  'tarifa_preferencial': 'Público',
                  'created_at': isoNow,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
          }
        }
      }

      // 4. Auto-bootstrap de Ventas y Tickets Históricos por Cliente (extraídos de Eleventa/Firebird)
      try {
        final clientVentasCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM ventas WHERE cliente_id IS NOT NULL AND cliente_id != 'PUBLICO-GRAL';",
        )) ?? 0;

        if (clientVentasCount == 0) {
          final ventasJsonString = await rootBundle.loadString('assets/ventas_historicas_clientes.json');
          if (ventasJsonString.isNotEmpty) {
            final List<dynamic> ventasList = jsonDecode(ventasJsonString);
            final batch = db.batch();
            final isoNow = DateTime.now().toUtc().toIso8601String();

            for (final v in ventasList) {
              final ventaMap = v as Map<String, dynamic>;
              final vId = ventaMap['id'] as String;
              final cId = ventaMap['cliente_id']?.toString() ?? 'PUBLICO-GRAL';
              final cNom = ventaMap['cliente_nombre']?.toString() ?? 'Público en General';

              batch.insert(
                'ventas',
                {
                  'id': vId,
                  'corte_caja_id': ventaMap['corte_caja_id'] ?? 'CORTE-FDB-CAJA-1',
                  'cliente_id': cId,
                  'cliente_nombre': cNom,
                  'folio_ticket': ventaMap['folio_ticket'],
                  'subtotal': (ventaMap['subtotal'] as num?)?.toDouble() ?? 0.0,
                  'descuento_total': (ventaMap['descuento_total'] as num?)?.toDouble() ?? 0.0,
                  'impuestos_total': (ventaMap['impuestos_total'] as num?)?.toDouble() ?? 0.0,
                  'total': (ventaMap['total'] as num?)?.toDouble() ?? 0.0,
                  'pagos_desglose': ventaMap['pagos_desglose'] ?? '[]',
                  'fecha_venta': ventaMap['fecha_venta'] ?? isoNow,
                  'estatus': ventaMap['estatus'] ?? 'completado',
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );

              final items = ventaMap['items'] as List<dynamic>? ?? [];
              for (final it in items) {
                final itemMap = it as Map<String, dynamic>;
                final prodId = itemMap['producto_id']?.toString() ?? 'ART-COMUN';
                final prodName = itemMap['nombre']?.toString() ?? prodId;

                // Asegurar integridad referencial con productos
                batch.insert(
                  'productos',
                  {
                    'id': prodId,
                    'codigo_barras': prodId,
                    'sku': prodId,
                    'nombre': prodName,
                    'descripcion': prodName,
                    'marca': 'Genérica',
                    'departamento': 'Residencial',
                    'departamentos_aplicables': 'Todos',
                    'precio_compra': 0.0,
                    'precio_venta': (itemMap['precio_historico'] as num?)?.toDouble() ?? 0.0,
                    'stock_actual': 0.0,
                    'stock_minimo': 0.0,
                    'es_a_granel': 0,
                    'es_servicio': 0,
                    'insumo_vinculado_id': null,
                    'cantidad_insumo': 1.0,
                    'created_at': isoNow,
                    'updated_at': isoNow,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );

                batch.insert(
                  'detalles_venta',
                  {
                    'id': itemMap['id'] ?? 'DET_${DateTime.now().microsecondsSinceEpoch}',
                    'venta_id': vId,
                    'producto_id': prodId,
                    'cantidad': (itemMap['cantidad'] as num?)?.toDouble() ?? 1.0,
                    'precio_historico': (itemMap['precio_historico'] as num?)?.toDouble() ?? 0.0,
                    'costo_historico': (itemMap['costo_historico'] as num?)?.toDouble() ?? 0.0,
                    'descuento_linea': (itemMap['descuento_linea'] as num?)?.toDouble() ?? 0.0,
                    'total_linea': (itemMap['total_linea'] as num?)?.toDouble() ?? 0.0,
                    'insumo_utilizado_id': null,
                    'cantidad_insumo_consumida': 0.0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            }
            await batch.commit(noResult: true);
          }
        }
      } catch (_) {}

      // 5. Auto-bootstrap de Abonos a Crédito Históricos por Cliente (extraídos de Eleventa/Firebird)
      try {
        final abonosCount = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM abonos_credito;",
        )) ?? 0;

        if (abonosCount == 0) {
          final abonosJsonString = await rootBundle.loadString('assets/abonos_historicos_clientes.json');
          if (abonosJsonString.isNotEmpty) {
            final List<dynamic> abonosList = jsonDecode(abonosJsonString);
            final batch = db.batch();
            final isoNow = DateTime.now().toUtc().toIso8601String();

            for (final a in abonosList) {
              final abonoMap = a as Map<String, dynamic>;
              final cId = abonoMap['cliente_id']?.toString() ?? 'PUBLICO-GRAL';
              final cNom = abonoMap['cliente_nombre']?.toString() ?? cId;

              // Asegurar existencia del cliente para clave foránea
              batch.insert(
                'clientes',
                {
                  'id': cId,
                  'nombre': cNom,
                  'limite_credito': 0.0,
                  'saldo_deudor': 0.0,
                  'activo': 1,
                  'tarifa_preferencial': 'Público',
                  'created_at': isoNow,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );

              batch.insert(
                'abonos_credito',
                {
                  'id': abonoMap['id'],
                  'cliente_id': cId,
                  'corte_caja_id': abonoMap['corte_caja_id'] ?? 'CORTE-FDB-ABONO',
                  'monto': (abonoMap['monto'] as num?)?.toDouble() ?? 0.0,
                  'fecha': abonoMap['fecha'] ?? isoNow,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
          }
        }
      } catch (_) {}
    } catch (_) {
      // Ignorar fallos de bootstrap si assets no están presentes en pruebas
    }
  }

  // Kardex de Inventario
  Future<void> logInventoryMovement({
    required DatabaseExecutor db,
    required String productoId,
    required String productoDesc,
    required String tipo,
    required double cantidad,
    required double stockAnterior,
    required double stockNuevo,
    required String usuarioId,
    String? departamento,
    String? motivo,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    _movSeq = (_movSeq + 1) % 100000;
    final id = 'MOV_${DateTime.now().microsecondsSinceEpoch}_$_movSeq';

    // Normalizar tipo para compatibilidad estricta con CHECK constraint de SQLite ('VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION')
    String safeTipo = tipo.toUpperCase();
    String? safeMotivo = motivo;
    if (safeTipo == 'VENTA_SERVICIO') {
      safeTipo = 'VENTA';
      if (safeMotivo == null || !safeMotivo.toLowerCase().contains('servicio')) {
        safeMotivo = '[Servicio] ${safeMotivo ?? ""}'.trim();
      }
    } else if (safeTipo == 'CANCELACION') {
      safeTipo = 'DEVOLUCION';
      if (safeMotivo == null || !safeMotivo.toLowerCase().contains('cancel')) {
        safeMotivo = '[Cancelación] ${safeMotivo ?? ""}'.trim();
      }
    } else if (!const {'VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION'}.contains(safeTipo)) {
      safeTipo = 'AJUSTE';
    }

    await db.insert('movimientos_inventario', {
      'id': id,
      'producto_id': productoId,
      'producto_desc': productoDesc,
      'tipo': safeTipo,
      'cantidad': cantidad,
      'stock_anterior': stockAnterior,
      'stock_nuevo': stockNuevo,
      'usuario_id': usuarioId,
      'departamento': departamento,
      'motivo': safeMotivo,
      'fecha': nowIso,
      'created_at': nowIso,
    });
  }

  Future<List<InventoryMovementRecord>> getInventoryMovements({int limit = 100}) async {
    final db = await database;
    final results = await db.query(
      'movimientos_inventario',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return results.map((r) => InventoryMovementRecord.fromMap(r)).toList();
  }

  // Metadatos y Sincronización
  Future<String?> getMetadata(String key) async {
    final db = await database;
    final results = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<void> setMetadata(String key, String value) async {
    final db = await database;
    final isoNow = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'app_metadata',
      {
        'key': key,
        'value': value,
        'updated_at': isoNow,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Configuración del Negocio y Sistema
  Future<String?> getConfig(String key) async {
    final db = await database;
    final results = await db.query(
      'configuracion_negocio',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<void> setConfig(String key, String value) async {
    final db = await database;
    final isoNow = DateTime.now().toUtc().toIso8601String();
    await db.insert(
      'configuracion_negocio',
      {
        'key': key,
        'value': value,
        'updated_at': isoNow,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAllConfig() async {
    final db = await database;
    final results = await db.query('configuracion_negocio');
    final Map<String, String> map = {};
    for (final r in results) {
      map[r['key'] as String] = r['value'] as String;
    }
    return map;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}