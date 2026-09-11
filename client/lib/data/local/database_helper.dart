import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

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
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  /// Configura pragmas de bajo nivel y baja latencia para hardware limitado
  Future<void> _onConfigure(Database db) async {
    // 1. Habilita integridad referencial
    await db.execute('PRAGMA foreign_keys = ON;');
    
    // 2. Modo WAL (Write-Ahead Logging): permite lecturas concurrentes sin bloquear escrituras
    await db.execute('PRAGMA journal_mode = WAL;');
    
    // 3. Sincronización normal: reduce la latencia de disco manteniendo durabilidad
    await db.execute('PRAGMA synchronous = NORMAL;');
  }

  /// Lee schema.sql desde los assets o ejecuta el DDL embebido
  Future<void> _createDB(Database db, int version) async {
    String schemaSql;
    try {
      // Carga el archivo schema.sql si está configurado en pubspec assets
      schemaSql = await rootBundle.loadString('lib/data/local/schema.sql');
    } catch (_) {
      // Fallback con el DDL exacto si el asset aún no fue enlazado
      schemaSql = _fallbackSchemaDDL;
    }

    // SQLite ejecuta múltiples sentencias separadas por punto y coma
    final statements = schemaSql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !s.startsWith('--'));

    for (final stmt in statements) {
      await db.execute(stmt);
    }
  }

  static const String _fallbackSchemaDDL = '''
    CREATE TABLE IF NOT EXISTS cortes_caja (
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
    );

    CREATE TABLE IF NOT EXISTS productos (
        id TEXT PRIMARY KEY NOT NULL,
        codigo_barras TEXT UNIQUE,
        sku TEXT UNIQUE,
        descripcion TEXT NOT NULL,
        precio_compra REAL NOT NULL DEFAULT 0.0,
        precio_venta REAL NOT NULL,
        porcentaje_impuesto REAL NOT NULL DEFAULT 0.0,
        departamento TEXT DEFAULT 'General',
        stock_actual REAL NOT NULL DEFAULT 0.0,
        es_a_granel INTEGER NOT NULL DEFAULT 0 CHECK (es_a_granel IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ventas (
        id TEXT PRIMARY KEY NOT NULL,
        corte_caja_id TEXT NOT NULL,
        folio_ticket TEXT,
        subtotal REAL NOT NULL,
        descuento_total REAL NOT NULL DEFAULT 0.0,
        impuestos_total REAL NOT NULL DEFAULT 0.0,
        total REAL NOT NULL,
        pagos_desglose TEXT NOT NULL,
        fecha_venta TEXT NOT NULL,
        FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
    );

    CREATE TABLE IF NOT EXISTS detalles_venta (
        id TEXT PRIMARY KEY NOT NULL,
        venta_id TEXT NOT NULL,
        producto_id TEXT NOT NULL,
        cantidad REAL NOT NULL,
        precio_historico REAL NOT NULL,
        costo_historico REAL NOT NULL DEFAULT 0.0,
        descuento_linea REAL NOT NULL DEFAULT 0.0,
        total_linea REAL NOT NULL,
        FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
        FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT
    );

    CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY NOT NULL,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_code TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_productos_codigo_barras ON productos(codigo_barras);
    CREATE INDEX IF NOT EXISTS idx_productos_sku ON productos(sku);
    CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created ON sync_queue(sync_status, created_at);
    CREATE INDEX IF NOT EXISTS idx_ventas_corte_id ON ventas(corte_caja_id);
    CREATE INDEX IF NOT EXISTS idx_detalles_venta_venta_id ON detalles_venta(venta_id);
  ''';

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}