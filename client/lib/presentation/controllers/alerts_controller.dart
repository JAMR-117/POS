import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/inventory/inventory_api_client.dart';
import '../../data/local/database_helper.dart';

/// Administrador de estado ligero y 100% Offline-First para alertas predictivas de inventario
class AlertsController extends ChangeNotifier {
  final DatabaseHelper _dbHelper;
  final InventoryApiClient? _apiClient;
  final double runwayDaysThreshold;

  AlertsController({
    DatabaseHelper? dbHelper,
    InventoryApiClient? apiClient,
    this.runwayDaysThreshold = 7.0,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _apiClient = apiClient;

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
      _alerts.where((a) => a.stockActual > 0 && (a.stockActual <= a.stockMinimo || a.diasRestantes <= runwayDaysThreshold)).length;

  /// Carga o refresca las alertas utilizando cálculo 100% local en SQLite (Offline-First)
  Future<void> loadAlerts({String? tiendaId, bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      // 1. Cálculo 100% Offline-First directo sobre la base SQLite local
      final localAlerts = await _calculateLocalStockAlerts();
      _alerts = localAlerts;
      _errorMessage = null;
      _lastFetchTime = DateTime.now();
    } catch (e) {
      // En caso de error local imprevisto, intentar como fallback el backend si fue configurado
      final client = _apiClient;
      if (client != null) {
        try {
          final fetched = await client.fetchStockAlerts(
            runwayDays: runwayDaysThreshold,
            tiendaId: tiendaId,
          );
          _alerts = fetched;
          _errorMessage = null;
          _lastFetchTime = DateTime.now();
        } catch (apiError) {
          _errorMessage = 'Error al calcular alertas: $e | API: $apiError';
        }
      } else {
        _errorMessage = 'Error al calcular alertas locales: $e';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StockAlertItem>> _calculateLocalStockAlerts() async {
    final db = await _dbHelper.database;
    final thirtyDaysAgoIso = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    // 1. Sumar ventas directas de los últimos 30 días
    final directSales = await db.rawQuery('''
      SELECT dv.producto_id, SUM(dv.cantidad) as total_vendido, MAX(v.fecha_venta) as ultima_fecha
      FROM detalles_venta dv
      JOIN ventas v ON dv.venta_id = v.id
      WHERE v.fecha_venta >= ? AND v.estatus != 'cancelado'
      GROUP BY dv.producto_id
    ''', [thirtyDaysAgoIso]);

    final Map<String, double> sales30dMap = {};
    final Map<String, DateTime> lastSaleMap = {};

    for (final row in directSales) {
      final pid = row['producto_id'] as String?;
      if (pid != null) {
        final cant = (row['total_vendido'] as num?)?.toDouble() ?? 0.0;
        sales30dMap[pid] = (sales30dMap[pid] ?? 0.0) + cant;
        final fechaStr = row['ultima_fecha'] as String?;
        if (fechaStr != null) {
          final dt = DateTime.tryParse(fechaStr);
          if (dt != null) lastSaleMap[pid] = dt;
        }
      }
    }

    // 2. Sumar consumo de insumos derivados de servicios en los últimos 30 días
    try {
      final insumoSales = await db.rawQuery('''
        SELECT p.insumo_vinculado_id as insumo_id, 
               SUM(dv.cantidad * COALESCE(p.cantidad_insumo, 1.0)) as total_insumo, 
               MAX(v.fecha_venta) as ultima_fecha
        FROM detalles_venta dv
        JOIN ventas v ON dv.venta_id = v.id
        JOIN productos p ON dv.producto_id = p.id
        WHERE v.fecha_venta >= ? 
          AND v.estatus != 'cancelado' 
          AND p.es_servicio = 1 
          AND p.insumo_vinculado_id IS NOT NULL 
          AND p.insumo_vinculado_id != ''
        GROUP BY p.insumo_vinculado_id
      ''', [thirtyDaysAgoIso]);

      for (final row in insumoSales) {
        final iid = row['insumo_id'] as String?;
        if (iid != null) {
          final cant = (row['total_insumo'] as num?)?.toDouble() ?? 0.0;
          sales30dMap[iid] = (sales30dMap[iid] ?? 0.0) + cant;
          final fechaStr = row['ultima_fecha'] as String?;
          if (fechaStr != null) {
            final dt = DateTime.tryParse(fechaStr);
            if (dt != null && (lastSaleMap[iid] == null || dt.isAfter(lastSaleMap[iid]!))) {
              lastSaleMap[iid] = dt;
            }
          }
        }
      }
    } catch (_) {
      // Ignorar si la tabla o relación está vacía
    }

    // 3. Consultar todos los productos físicos (es_servicio = 0)
    final prodRows = await db.query(
      'productos',
      where: 'es_servicio = 0',
    );

    final List<StockAlertItem> result = [];

    for (final row in prodRows) {
      final id = row['id'] as String;
      final nombre = row['nombre'] as String? ?? '';
      final descripcion = row['descripcion'] as String? ?? nombre;
      final fullDesc = nombre.isNotEmpty ? (descripcion.isNotEmpty && descripcion != nombre ? '$nombre ($descripcion)' : nombre) : descripcion;
      final double stockActual = (row['stock_actual'] as num?)?.toDouble() ?? 0.0;
      final double stockMinimo = (row['stock_minimo'] as num?)?.toDouble() ?? 5.0;
      final String? barcode = row['codigo_barras'] as String?;
      final String? sku = row['sku'] as String?;

      final double ventas30d = sales30dMap[id] ?? 0.0;
      final double velocidadDiaria = ventas30d / 30.0;
      final double diasRestantes = velocidadDiaria > 0.0
          ? (stockActual / velocidadDiaria)
          : (stockActual <= stockMinimo ? 0.0 : 9999.0);

      final bool esBajoMinimo = stockActual <= stockMinimo;
      final bool esAgotado = stockActual <= 0.0;
      final bool esRunwayBajo = diasRestantes <= runwayDaysThreshold;

      if (esAgotado || esBajoMinimo || esRunwayBajo) {
        RiskLevel nivel;
        if (esAgotado) {
          nivel = RiskLevel.critico;
        } else if (esBajoMinimo) {
          nivel = RiskLevel.alto;
        } else {
          nivel = RiskLevel.moderado;
        }

        result.add(
          StockAlertItem(
            id: id,
            tiendaId: 'LOCAL',
            codigoBarras: barcode,
            sku: sku,
            descripcion: fullDesc,
            stockActual: stockActual,
            stockMinimo: stockMinimo,
            ventasUltimos30Dias: ventas30d,
            velocidadDiaria: velocidadDiaria,
            diasRestantes: diasRestantes,
            nivelRiesgo: nivel,
            ultimaVentaAt: lastSaleMap[id],
          ),
        );
      }
    }

    // Ordenar: primero agotados (stockActual <= 0), luego por nivel de riesgo y menor días restantes
    result.sort((a, b) {
      if (a.stockActual <= 0 && b.stockActual > 0) return -1;
      if (a.stockActual > 0 && b.stockActual <= 0) return 1;
      return a.diasRestantes.compareTo(b.diasRestantes);
    });

    return result;
  }

  @override
  void dispose() {
    _apiClient?.dispose();
    super.dispose();
  }
}