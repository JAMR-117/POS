import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';
import 'sync_api_client.dart';
import 'sync_models.dart';

class SyncWorker extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final SyncApiClient _apiClient;
  final int batchSize;
  final Duration interval;

  Timer? _pollingTimer;
  bool _isProcessing = false;
  bool _isOnline = true;
  int _pendingCount = 0;
  SyncStatusState _status = SyncStatusState.synced;
  DateTime? _lastSyncTime;

  // Backoff exponencial base (segundos)
  static const int _baseBackoffSeconds = 5;
  static const int _maxBackoffSeconds = 300; // Tope: 5 minutos

  SyncWorker({
    DatabaseHelper? dbHelper,
    required SyncApiClient apiClient,
    this.batchSize = 25,
    this.interval = const Duration(seconds: 10),
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _apiClient = apiClient;

  // Getters reactivos para la UI de la terminal
  SyncStatusState get status => _status;
  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Inicializa el ciclo de vida del despachador
  void start() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => processPendingQueue());
    Future.microtask(() => processPendingQueue());
  }

  /// Alias explícito para inicializar el temporizador en main.dart
  void startPeriodicWorker() => start();

  /// Dispara la sincronización inmediatamente tras cualquier transacción
  void triggerSyncNow() {
    Future.microtask(() => processPendingQueue());
  }

  /// Detiene el worker limpiamente
  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Verifica conectividad activa real mediante HTTP health check (compatible Web y Desktop)
  Future<bool> checkConnectivity() async {
    return await _apiClient.checkHealth();
  }

  /// Ciclo bidireccional completo: Push de cola local + Pull de actualizaciones centrales
  Future<void> processPendingQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. Verificación de enlace activo con timeout de 3s
      final online = await checkConnectivity();
      if (!online) {
        _isOnline = false;
        await _refreshPendingCount();
        _updateStatus(SyncStatusState.offline);
        return;
      }
      _isOnline = true;

      // 2. Extraer lote pendiente de sync_queue (PUSH)
      final events = await _fetchPendingBatch();
      await _refreshPendingCount();

      if (events.isNotEmpty) {
        _updateStatus(SyncStatusState.syncing);

        // Despachar hacia el backend de Go
        final response = await _apiClient.sendBatch(events);

        // Procesar transiciones de estado en SQLite
        await _handleServerAcks(response.acknowledgedIds, response.errors, events);
      }

      // 3. Descargar actualizaciones desde PostgreSQL (PULL)
      await _pullServerUpdates();

      await _refreshPendingCount();
      _lastSyncTime = DateTime.now();
      _updateStatus(_pendingCount > 0 ? SyncStatusState.pendingSync : SyncStatusState.synced);
    } on SyncApiException catch (e) {
      await _applyNetworkFailureBackoff(e.message);
      _isOnline = false;
      _updateStatus(SyncStatusState.offline);
    } catch (_) {
      _isOnline = false;
      _updateStatus(SyncStatusState.offline);
    } finally {
      _isProcessing = false;
    }
  }

  /// Descarga catálogo actualizado de productos y clientes desde PostgreSQL y los refleja en SQLite
  Future<void> _pullServerUpdates() async {
    try {
      final pullData = await _apiClient.pullUpdates();
      final products = pullData['products'] as List<dynamic>?;
      final clients = pullData['clients'] as List<dynamic>?;

      final db = await _dbHelper.database;
      final isoNow = DateTime.now().toUtc().toIso8601String();

      if (products != null && products.isNotEmpty) {
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final p in products) {
            final pMap = p as Map<String, dynamic>;
            final pid = pMap['id'] as String?;
            if (pid == null || pid.isEmpty) continue;

            batch.insert(
              'productos',
              {
                'id': pid,
                'codigo_barras': pMap['codigo_barras'],
                'sku': pMap['sku'],
                'nombre': pMap['nombre'] ?? '',
                'descripcion': pMap['descripcion'] ?? '',
                'marca': pMap['marca'] ?? 'Genérica',
                'codigo_equivalencia': pMap['codigo_equivalencia'],
                'ubicacion': pMap['ubicacion'],
                'precio_compra': (pMap['precio_compra'] as num?)?.toDouble() ?? 0.0,
                'precio_venta': (pMap['precio_venta'] as num?)?.toDouble() ?? 0.0,
                'precio_cerrajero': (pMap['precio_cerrajero'] as num?)?.toDouble(),
                'precio_taller': (pMap['precio_taller'] as num?)?.toDouble(),
                'precio_mayoreo': (pMap['precio_mayoreo'] as num?)?.toDouble(),
                'cantidad_mayoreo': (pMap['cantidad_mayoreo'] as num?)?.toDouble(),
                'stock_actual': (pMap['stock_actual'] as num?)?.toDouble() ?? 0.0,
                'stock_minimo': (pMap['stock_minimo'] as num?)?.toDouble() ?? 5.0,
                'es_a_granel': (pMap['es_a_granel'] as int?) ?? 0,
                'es_servicio': (pMap['es_servicio'] as int?) ?? 0,
                'insumo_vinculado_id': pMap['insumo_vinculado_id'],
                'cantidad_insumo': (pMap['cantidad_insumo'] as num?)?.toDouble() ?? 1.0,
                'ventas_ultimos_30dias': (pMap['ventas_ultimos_30dias'] as num?)?.toDouble() ?? 0.0,
                'total_unidades_vendidas': (pMap['total_unidades_vendidas'] as num?)?.toDouble() ?? 0.0,
                'departamento': pMap['departamento'] ?? 'General',
                'created_at': isoNow,
                'updated_at': pMap['updated_at'] ?? isoNow,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        });
      }

      if (clients != null && clients.isNotEmpty) {
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final c in clients) {
            final cMap = c as Map<String, dynamic>;
            final cid = cMap['id'] as String?;
            if (cid == null || cid.isEmpty) continue;

            batch.insert(
              'clientes',
              {
                'id': cid,
                'nombre': cMap['nombre'] ?? '',
                'telefono': cMap['telefono'],
                'email': cMap['email'],
                'direccion': cMap['direccion'],
                'limite_credito': (cMap['limite_credito'] as num?)?.toDouble() ?? 0.0,
                'saldo_actual': (cMap['saldo_deudor'] as num?)?.toDouble() ?? 0.0,
                'created_at': isoNow,
                'updated_at': cMap['updated_at'] ?? isoNow,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        });
      }
    } catch (_) {
      // Ignorar fallos de pull si hay problemas momentáneos
    }
  }

  /// Consulta pendientes en sync_queue
  Future<List<SyncEvent>> _fetchPendingBatch() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> records = await db.query(
      'sync_queue',
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC',
      limit: batchSize,
    );

    return records.map((row) => SyncEvent.fromMap(row)).toList();
  }

  /// Aplica ACKs y rechazos individuales recibidos de Go
  Future<void> _handleServerAcks(
    List<String> ackIds,
    Map<String, String> errorMap,
    List<SyncEvent> sentEvents,
  ) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      for (final id in ackIds) {
        await txn.update(
          'sync_queue',
          {
            'sync_status': 'synced',
            'synced_at': nowIso,
            'error_code': null,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      for (final entry in errorMap.entries) {
        final id = entry.key;
        final errorCode = entry.value;

        await txn.rawUpdate('''
          UPDATE sync_queue 
          SET retry_count = retry_count + 1,
              error_code = ?,
              sync_status = CASE WHEN retry_count >= 5 THEN 'failed' ELSE 'pending' END
          WHERE id = ?
        ''', [errorCode, id]);
      }
    });
  }

  /// Maneja caídas abruptas de red durante la llamada HTTP
  Future<void> _applyNetworkFailureBackoff(String errorMsg) async {
    final db = await _dbHelper.database;
    await db.rawUpdate('''
      UPDATE sync_queue 
      SET retry_count = retry_count + 1,
          error_code = ?
      WHERE sync_status = 'pending'
    ''', [errorMsg]);
  }

  Future<void> _refreshPendingCount() async {
    final db = await _dbHelper.database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM sync_queue WHERE sync_status = 'pending'",
    ));
    _pendingCount = count ?? 0;
  }

  void _updateStatus(SyncStatusState newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }

  int calculateBackoffSeconds(int retryCount) {
    final exponential = _baseBackoffSeconds * pow(2, retryCount).toInt();
    return min(exponential, _maxBackoffSeconds);
  }

  @override
  void dispose() {
    stop();
    _apiClient.dispose();
    super.dispose();
  }
}
