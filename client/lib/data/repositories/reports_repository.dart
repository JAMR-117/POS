import '../local/database_helper.dart';

class TopProductProfit {
  final String descripcion;
  final double cantidadVendida;
  final double utilidadGenerada;

  TopProductProfit({
    required this.descripcion,
    required this.cantidadVendida,
    required this.utilidadGenerada,
  });
}

class ProfitReportSummary {
  final double totalVentas;
  final double cogs; // Cost of Goods Sold (Costo de lo vendido)
  final double gananciaBruta;
  final double margenPorcentual;
  final List<TopProductProfit> topProductos;

  ProfitReportSummary({
    required this.totalVentas,
    required this.cogs,
    required this.gananciaBruta,
    required this.margenPorcentual,
    required this.topProductos,
  });
}

class ReportsRepository {
  final DatabaseHelper _dbHelper;

  ReportsRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Genera el reporte de utilidades agrupando y sumando directamente en SQLite
  Future<ProfitReportSummary> getGrossProfitReport(DateTime start, DateTime end) async {
    final db = await _dbHelper.database;
    
    // Formateo estricto ISO8601 para que SQLite evalúe correctamente los rangos (alfanuméricamente)
    final startStr = start.toUtc().toIso8601String();
    final endStr = end.toUtc().toIso8601String();

    // 1. KPI Globales (Suma de toda la venta en el periodo)
    final kpiResults = await db.rawQuery('''
      SELECT 
        SUM((dv.precio_historico * dv.cantidad) - dv.descuento_linea) as total_ventas,
        SUM(dv.costo_historico * dv.cantidad) as total_costos,
        SUM(((dv.precio_historico - dv.costo_historico) * dv.cantidad) - dv.descuento_linea) as ganancia_bruta
      FROM detalles_venta dv
      INNER JOIN ventas v ON v.id = dv.venta_id
      WHERE v.estatus = 'completado'
        AND v.fecha_venta >= ? AND v.fecha_venta <= ?
    ''', [startStr, endStr]);

    double ventas = 0.0, costos = 0.0, ganancia = 0.0;
    
    if (kpiResults.isNotEmpty && kpiResults.first['total_ventas'] != null) {
      ventas = (kpiResults.first['total_ventas'] as num).toDouble();
      costos = (kpiResults.first['total_costos'] as num).toDouble();
      ganancia = (kpiResults.first['ganancia_bruta'] as num).toDouble();
    }

    final margen = ventas > 0 ? (ganancia / ventas) * 100 : 0.0;

    // 2. Top 10 Productos Más Rentables
    final topResults = await db.rawQuery('''
      SELECT 
        p.descripcion,
        SUM(dv.cantidad) as unidades,
        SUM(((dv.precio_historico - dv.costo_historico) * dv.cantidad) - dv.descuento_linea) as utilidad
      FROM detalles_venta dv
      INNER JOIN ventas v ON v.id = dv.venta_id
      LEFT JOIN productos p ON p.id = dv.producto_id
      WHERE v.estatus = 'completado'
        AND v.fecha_venta >= ? AND v.fecha_venta <= ?
      GROUP BY dv.producto_id
      ORDER BY utilidad DESC
      LIMIT 10
    ''', [startStr, endStr]);

    final topProductos = topResults.map((row) => TopProductProfit(
      descripcion: row['descripcion'] as String? ?? 'Producto Eliminado',
      cantidadVendida: (row['unidades'] as num).toDouble(),
      utilidadGenerada: (row['utilidad'] as num).toDouble(),
    )).toList();

    return ProfitReportSummary(
      totalVentas: ventas,
      cogs: costos,
      gananciaBruta: ganancia,
      margenPorcentual: margen,
      topProductos: topProductos,
    );
  }
}