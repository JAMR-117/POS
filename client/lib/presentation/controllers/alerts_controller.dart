import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/inventory/inventory_api_client.dart';

/// Administrador de estado ligero y no bloqueante para las alertas predictivas de inventario
class AlertsController extends ChangeNotifier {
  final InventoryApiClient _apiClient;
  final double runwayDaysThreshold;

  AlertsController({
    InventoryApiClient? apiClient,
    this.runwayDaysThreshold = 7.0,
  }) : _apiClient = apiClient ?? InventoryApiClient();

  List<StockAlertItem> _alerts = [];
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchTime;

  // Getters inmutables
  List<StockAlertItem> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetchTime => _lastFetchTime;
  int get totalAlertsCount => _alerts.length;

  /// Cantidad de productos en quiebre total de inventario (stock <= 0)
  int get criticalCount => _alerts.where((a) => a.stockActual <= 0).length;

  /// Cantidad de productos próximos a quebrar stock comercialmente
  int get warningCount =>
      _alerts.where((a) => a.stockActual > 0 && a.diasRestantes <= runwayDaysThreshold).length;

  /// Carga o refresca las alertas sin congelar el hilo principal de renderizado
  Future<void> loadAlerts({String? tiendaId, bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final fetched = await _apiClient.fetchStockAlerts(
        runwayDays: runwayDaysThreshold,
        tiendaId: tiendaId,
      );

      _alerts = fetched;
      _errorMessage = null;
      _lastFetchTime = DateTime.now();
    } catch (e) {
      _errorMessage = e.toString();
      // En modo silencioso (ej. segundo plano), mantenemos los datos en caché previos si falló la red
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }
}