/// Entidad que representa un producto del catálogo local
class Product {
  final String id;
  final String? codigoBarras;
  final String? sku;
  final String descripcion;
  final double precioCompra;
  final double precioVenta;
  final double porcentajeImpuesto;
  final String departamento;
  final double stockActual;
  final bool esAGranel;

  Product({
    required this.id,
    this.codigoBarras,
    this.sku,
    required this.descripcion,
    required this.precioCompra,
    required this.precioVenta,
    required this.porcentajeImpuesto,
    required this.departamento,
    required this.stockActual,
    required this.esAGranel,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      codigoBarras: map['codigo_barras'] as String?,
      sku: map['sku'] as String?,
      descripcion: map['descripcion'] as String,
      precioCompra: (map['precio_compra'] as num).toDouble(),
      precioVenta: (map['precio_venta'] as num).toDouble(),
      porcentajeImpuesto: (map['porcentaje_impuesto'] as num).toDouble(),
      departamento: map['departamento'] as String? ?? 'General',
      stockActual: (map['stock_actual'] as num).toDouble(),
      esAGranel: (map['es_a_granel'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo_barras': codigoBarras,
      'sku': sku,
      'descripcion': descripcion,
      'precio_compra': precioCompra,
      'precio_venta': precioVenta,
      'porcentaje_impuesto': porcentajeImpuesto,
      'departamento': departamento,
      'stock_actual': stockActual,
      'es_a_granel': esAGranel ? 1 : 0,
    };
  }
}

/// Representa una partida individual dentro del ticket
class SaleDetailItem {
  final String id;
  final String productoId;
  final String descripcion; // Incluido para el snapshot del payload JSON
  final double cantidad;     // Permite valores decimales (ej: 0.450 kg)
  final double precioHistorico;
  final double costoHistorico;
  final double descuentoLinea;
  final double totalLinea;

  SaleDetailItem({
    required this.id,
    required this.productoId,
    required this.descripcion,
    required this.cantidad,
    required this.precioHistorico,
    this.costoHistorico = 0.0,
    this.descuentoLinea = 0.0,
    required this.totalLinea,
  });

  Map<String, dynamic> toMap(String ventaId) {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': productoId,
      'cantidad': cantidad,
      'precio_historico': precioHistorico,
      'costo_historico': costoHistorico,
      'descuento_linea': descuentoLinea,
      'total_linea': totalLinea,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto_id': productoId,
      'descripcion': descripcion,
      'cantidad': cantidad,
      'precio_historico': precioHistorico,
      'costo_historico': costoHistorico,
      'descuento_linea': descuentoLinea,
      'total_linea': totalLinea,
    };
  }
}

/// Desglose de pagos para transacciones mixtas
class PaymentMethodBreakdown {
  final String metodo; // 'efectivo', 'tarjeta', 'transferencia'
  final double monto;

  PaymentMethodBreakdown({required this.metodo, required this.monto});

  Map<String, dynamic> toJson() => {'metodo': metodo, 'monto': monto};

  factory PaymentMethodBreakdown.fromJson(Map<String, dynamic> json) {
    return PaymentMethodBreakdown(
      metodo: json['metodo'] as String,
      monto: (json['monto'] as num).toDouble(),
    );
  }
}

/// Solicitud de Venta Completa
class SaleTransactionRequest {
  final String ventaId;
  final String corteCajaId;
  final String? folioTicket;
  final double subtotal;
  final double descuentoTotal;
  final double impuestosTotal;
  final double total;
  final List<PaymentMethodBreakdown> pagosDesglose;
  final List<SaleDetailItem> items;
  final DateTime fechaVenta;

  SaleTransactionRequest({
    required this.ventaId,
    required this.corteCajaId,
    this.folioTicket,
    required this.subtotal,
    this.descuentoTotal = 0.0,
    this.impuestosTotal = 0.0,
    required this.total,
    required this.pagosDesglose,
    required this.items,
    DateTime? fechaVenta,
  }) : fechaVenta = fechaVenta ?? DateTime.now().toUtc();
}