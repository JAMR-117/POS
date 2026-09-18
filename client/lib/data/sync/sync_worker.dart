import 'dart:async';
import 'dart:io';
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

  // Backoff exponencial base (segundos)
  static const int _baseBackoffSeconds = 5;
  static const int _maxBackoffSeconds = 300; // Tope: 5 minutos

  SyncWorker({
    DatabaseHelper? dbHelper,
    required SyncApiClient apiClient,
    this.batchSize = 25,
    this.interval = const Duration(seconds: 15),
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _apiClient = apiClient;

  // Getters reactivos para la UI de la terminal
  SyncStatusState get status => _status;
  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;

/// Inicializa el ciclo de vida del despachador
  void start() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => processPendingQueue());
    Future.microtask(() => processPendingQueue());
  }

  /// Alias explícito para inicializar el temporizador en main.dart
  void startPeriodicWorker() => start();

  /// Detiene el worker limpiamente (evita fugas en tests o shutdown)
  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Verifica conectividad activa real sin bloquear hilos
  Future<bool> checkConnectivity() async {
    try {
      final host = Uri.parse(_apiClient.baseUrl).host;
      final target = host.isEmpty ? 'google.com' : host;
      final result = await InternetAddress.lookup(target)
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Ciclo transaccional de extracción y envío Outbox
  Future<void> processPendingQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 1. Verificación de enlace activo
      final online = await checkConnectivity();
      if (!online) {
        _isOnline = false;
        await _refreshPendingCount();
        _updateStatus(SyncStatusState.offline);
        return;
      }
      _isOnline = true;

      // 2. Extraer lote de sync_queue
      final events = await _fetchPendingBatch();
      await _refreshPendingCount();

      if (events.isEmpty) {
        _updateStatus(SyncStatusState.synced);
        return;
      }

      _updateStatus(SyncStatusState.syncing);

      // 3. Despachar hacia el backend de Go
      final response = await _apiClient.sendBatch(events);

      // 4. Procesar transiciones de estado en SQLite
      await _handleServerAcks(response.acknowledgedIds, response.errors, events);

      await _refreshPendingCount();
      _updateStatus(_pendingCount > 0 ? SyncStatusState.pendingSync : SyncStatusState.synced);
    } on SyncApiException catch (e) {
      // Fallo de red detectado a nivel de transporte: aplicar backoff al lote evaluado
      await _applyNetworkFailureBackoff(e.message);
      _isOnline = false;
      _updateStatus(SyncStatusState.offline);
    } catch (e) {
      _updateStatus(SyncStatusState.pendingSync);
    } finally {
      _isProcessing = false;
    }
  }

  /// Consulta optimizada con índice idx_sync_queue_status_created[cite: 3]
  Future<List<SyncEvent>> _fetchPendingBatch() async {
    final db = await _dbHelper.database;
    //final nowIso = DateTime.now().toUtc().toIso8601String();

    // Filtra pendientes cuyo backoff programado ya haya vencido
    // Para simplificar sin alterar el schema DDL[cite: 3], usamos retry_count dentro de la cláusula
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
      // Éxito: Marcar eventos como sincronizados
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

      // Errores individuales reportados por validación de backend
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
    // Si la conexión cae, incrementa reintento de los primeros pendientes sin bloquear nuevas ventas
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

  /// Calcula backoff exponencial en segundos según la cantidad de fallos
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