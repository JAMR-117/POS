import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Nivel de criticidad para abastecimiento
enum RiskLevel {
  critico,
  alto,
  moderado,
  desconocido;

  static RiskLevel fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'CRITICO':
        return RiskLevel.critico;
      case 'ALTO':
        return RiskLevel.alto;
      case 'MODERADO':
        return RiskLevel.moderado;
      default:
        return RiskLevel.desconocido;
    }
  }
}

/// Representación inmutable de un elemento del listado predictivo de quiebre
class StockAlertItem {
  final String id;
  final String tiendaId;
  final String? codigoBarras;
  final String? sku;
  final String descripcion;
  final double stockActual;        // Soporta unidades enteras y granel decimal
  final double stockMinimo;
  final double ventasUltimos30Dias;
  final double velocidadDiaria;     // Salida calculada por día
  final double diasRestantes;       // Runway proyectado
  final RiskLevel nivelRiesgo;
  final DateTime? ultimaVentaAt;

  const StockAlertItem({
    required this.id,
    required this.tiendaId,
    this.codigoBarras,
    this.sku,
    required this.descripcion,
    required this.stockActual,
    required this.stockMinimo,
    required this.ventasUltimos30Dias,
    required this.velocidadDiaria,
    required this.diasRestantes,
    required this.nivelRiesgo,
    this.ultimaVentaAt,
  });

  factory StockAlertItem.fromJson(Map<String, dynamic> json) {
    return StockAlertItem(
      id: json['id'] as String,
      tiendaId: json['tienda_id'] as String? ?? '',
      codigoBarras: json['codigo_barras'] as String?,
      sku: json['sku'] as String?,
      descripcion: json['descripcion'] as String? ?? 'Sin descripción',
      stockActual: (json['stock_actual'] as num?)?.toDouble() ?? 0.0,
      stockMinimo: (json['stock_minimo'] as num?)?.toDouble() ?? 5.0,
      ventasUltimos30Dias: (json['ventas_ultimos_30dias'] as num?)?.toDouble() ?? 0.0,
      velocidadDiaria: (json['velocidad_diaria'] as num?)?.toDouble() ?? 0.0,
      diasRestantes: (json['dias_restantes'] as num?)?.toDouble() ?? 9999.0,
      nivelRiesgo: RiskLevel.fromString(json['nivel_riesgo'] as String?),
      ultimaVentaAt: json['ultima_venta_at'] != null
          ? DateTime.tryParse(json['ultima_venta_at'] as String)
          : null,
    );
  }
}

/// Elemento del catálogo general clasificado por volumen y velocidad comercial
class VelocityCatalogItem {
  final String id;
  final String tiendaId;
  final String? codigoBarras;
  final String? sku;
  final String descripcion;
  final String departamento;
  final double stockActual;
  final double totalUnidadesVendidas;
  final double ventasUltimos30Dias;
  final double velocidadDiaria;
  final double diasRestantes;
  final DateTime? ultimaVentaAt;

  const VelocityCatalogItem({
    required this.id,
    required this.tiendaId,
    this.codigoBarras,
    this.sku,
    required this.descripcion,
    required this.departamento,
    required this.stockActual,
    required this.totalUnidadesVendidas,
    required this.ventasUltimos30Dias,
    required this.velocidadDiaria,
    required this.diasRestantes,
    this.ultimaVentaAt,
  });

  factory VelocityCatalogItem.fromJson(Map<String, dynamic> json) {
    return VelocityCatalogItem(
      id: json['id'] as String,
      tiendaId: json['tienda_id'] as String? ?? '',
      codigoBarras: json['codigo_barras'] as String?,
      sku: json['sku'] as String?,
      descripcion: json['descripcion'] as String? ?? 'Sin descripción',
      departamento: json['departamento'] as String? ?? 'General',
      stockActual: (json['stock_actual'] as num?)?.toDouble() ?? 0.0,
      totalUnidadesVendidas: (json['total_unidades_vendidas'] as num?)?.toDouble() ?? 0.0,
      ventasUltimos30Dias: (json['ventas_ultimos_30dias'] as num?)?.toDouble() ?? 0.0,
      velocidadDiaria: (json['velocidad_diaria'] as num?)?.toDouble() ?? 0.0,
      diasRestantes: (json['dias_restantes'] as num?)?.toDouble() ?? 9999.0,
      ultimaVentaAt: json['ultima_venta_at'] != null
          ? DateTime.tryParse(json['ultima_venta_at'] as String)
          : null,
    );
  }
}

/// Cliente HTTP de bajo consumo para consultar endpoints analíticos
class InventoryApiClient {
  final String baseUrl;
  final http.Client _httpClient;

  InventoryApiClient({
    String? baseUrl,
    http.Client? httpClient,
  })  : baseUrl = baseUrl ?? 'http://127.0.0.1:8080',
        _httpClient = httpClient ?? http.Client();

  /// Obtiene alertas predictivas de escasez priorizadas por velocidad de venta
  Future<List<StockAlertItem>> fetchStockAlerts({
    double runwayDays = 7.0,
    String? tiendaId,
  }) async {
    final queryParams = <String, String>{
      'runway_days': runwayDays.toString(),
    };
    if (tiendaId != null && tiendaId.isNotEmpty) {
      queryParams['tienda_id'] = tiendaId;
    }

    final uri = Uri.parse('$baseUrl/api/v1/inventory/alerts').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> alertsJson = body['alerts'] as List<dynamic>? ?? [];
        return alertsJson
            .map((item) => StockAlertItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('HTTP_${response.statusCode}: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('TIMEOUT: El servidor no respondió a tiempo.');
    } catch (e) {
      throw Exception('NETWORK_ERROR: No se pudo consultar alertas ($e)');
    }
  }

  /// Consulta el catálogo general clasificado por rotación y ventas
  Future<List<VelocityCatalogItem>> fetchVelocityCatalog({
    String sort = 'sales_desc',
    int limit = 50,
    int offset = 0,
    String? tiendaId,
  }) async {
    final queryParams = <String, String>{
      'sort': sort,
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (tiendaId != null && tiendaId.isNotEmpty) {
      queryParams['tienda_id'] = tiendaId;
    }

    final uri = Uri.parse('$baseUrl/api/v1/inventory/velocity').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> itemsJson = body['items'] as List<dynamic>? ?? [];
        return itemsJson
            .map((item) => VelocityCatalogItem.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('HTTP_${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('CATALOG_ERROR: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}