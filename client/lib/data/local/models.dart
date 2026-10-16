class Product {
  final String id;
  final String? codigoBarras;
  final String? sku;
  final String nombre;
  final String descripcion;
  final String? marca;
  final String? codigoEquivalencia;
  final String? ubicacion;
  final double precioCompra;
  final double precioVenta; // Nivel 1: Público Casual
  final double? precioCerrajero; // Nivel 2: Colega Cerrajero / Gremio
  final double? precioTaller; // Nivel 3: Taller Automotriz / Especial
  final double porcentajeImpuesto;
  final String departamento;
  final double stockActual;
  final double stockMinimo; // Alerta de reabastecimiento
  final bool esAGranel;
  final double? cantidadMayoreo; // Nivel 4: Volumen
  final double? precioMayoreo;
  final bool esServicio;
  final String? insumoVinculadoId;
  final double cantidadInsumo;

  Product({
    required this.id,
    this.codigoBarras,
    this.sku,
    required this.nombre,
    required this.descripcion,
    this.marca,
    this.codigoEquivalencia,
    this.ubicacion,
    required this.precioCompra,
    required this.precioVenta,
    this.precioCerrajero,
    this.precioTaller,
    this.porcentajeImpuesto = 0.0,
    this.departamento = 'General',
    required this.stockActual,
    this.stockMinimo = 5.0,
    this.esAGranel = false,
    this.cantidadMayoreo,
    this.precioMayoreo,
    this.esServicio = false,
    this.insumoVinculadoId,
    this.cantidadInsumo = 1.0,
  });

  bool get hasWholesalePrice =>
      cantidadMayoreo != null &&
      precioMayoreo != null &&
      cantidadMayoreo! > 0 &&
      precioMayoreo! > 0;

  bool get isServiceWithInput =>
      esServicio &&
      insumoVinculadoId != null &&
      insumoVinculadoId!.trim().isNotEmpty;

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawDesc = map['descripcion'] as String? ?? '';
    final rawNombre = map['nombre'] as String?;
    return Product(
      id: map['id'] as String,
      codigoBarras: map['codigo_barras'] as String?,
      sku: map['sku'] as String?,
      nombre: (rawNombre != null && rawNombre.isNotEmpty) ? rawNombre : (rawDesc.isNotEmpty ? rawDesc : 'Sin Nombre'),
      descripcion: rawDesc,
      marca: map['marca'] as String?,
      codigoEquivalencia: map['codigo_equivalencia'] as String?,
      ubicacion: map['ubicacion'] as String?,
      precioCompra: (map['precio_compra'] as num?)?.toDouble() ?? 0.0,
      precioVenta: (map['precio_venta'] as num?)?.toDouble() ?? 0.0,
      precioCerrajero: (map['precio_cerrajero'] as num?)?.toDouble(),
      precioTaller: (map['precio_taller'] as num?)?.toDouble(),
      porcentajeImpuesto: (map['porcentaje_impuesto'] as num?)?.toDouble() ?? 0.0,
      departamento: map['departamento'] as String? ?? 'General',
      stockActual: (map['stock_actual'] as num?)?.toDouble() ?? 0.0,
      stockMinimo: (map['stock_minimo'] as num?)?.toDouble() ?? 5.0,
      esAGranel: (map['es_a_granel'] as int? ?? 0) == 1,
      cantidadMayoreo: (map['cantidad_mayoreo'] as num?)?.toDouble(),
      precioMayoreo: (map['precio_mayoreo'] as num?)?.toDouble(),
      esServicio: (map['es_servicio'] as int? ?? 0) == 1,
      insumoVinculadoId: map['insumo_vinculado_id'] as String?,
      cantidadInsumo: (map['cantidad_insumo'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo_barras': codigoBarras,
      'sku': sku,
      'nombre': nombre,
      'descripcion': descripcion,
      'marca': marca,
      'codigo_equivalencia': codigoEquivalencia,
      'ubicacion': ubicacion,
      'precio_compra': precioCompra,
      'precio_venta': precioVenta,
      'precio_cerrajero': precioCerrajero,
      'precio_taller': precioTaller,
      'porcentaje_impuesto': porcentajeImpuesto,
      'departamento': departamento,
      'stock_actual': stockActual,
      'stock_minimo': stockMinimo,
      'es_a_granel': esAGranel ? 1 : 0,
      'cantidad_mayoreo': cantidadMayoreo,
      'precio_mayoreo': precioMayoreo,
      'es_servicio': esServicio ? 1 : 0,
      'insumo_vinculado_id': insumoVinculadoId,
      'cantidad_insumo': cantidadInsumo,
    };
  }

  Product copyWith({
    String? id,
    String? codigoBarras,
    String? sku,
    String? nombre,
    String? descripcion,
    String? marca,
    String? codigoEquivalencia,
    String? ubicacion,
    double? precioCompra,
    double? precioVenta,
    double? precioCerrajero,
    double? precioTaller,
    double? porcentajeImpuesto,
    String? departamento,
    double? stockActual,
    double? stockMinimo,
    bool? esAGranel,
    double? cantidadMayoreo,
    double? precioMayoreo,
    bool? esServicio,
    String? insumoVinculadoId,
    double? cantidadInsumo,
  }) {
    return Product(
      id: id ?? this.id,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      sku: sku ?? this.sku,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      marca: marca ?? this.marca,
      codigoEquivalencia: codigoEquivalencia ?? this.codigoEquivalencia,
      ubicacion: ubicacion ?? this.ubicacion,
      precioCompra: precioCompra ?? this.precioCompra,
      precioVenta: precioVenta ?? this.precioVenta,
      precioCerrajero: precioCerrajero ?? this.precioCerrajero,
      precioTaller: precioTaller ?? this.precioTaller,
      porcentajeImpuesto: porcentajeImpuesto ?? this.porcentajeImpuesto,
      departamento: departamento ?? this.departamento,
      stockActual: stockActual ?? this.stockActual,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      esAGranel: esAGranel ?? this.esAGranel,
      cantidadMayoreo: cantidadMayoreo ?? this.cantidadMayoreo,
      precioMayoreo: precioMayoreo ?? this.precioMayoreo,
      esServicio: esServicio ?? this.esServicio,
      insumoVinculadoId: insumoVinculadoId ?? this.insumoVinculadoId,
      cantidadInsumo: cantidadInsumo ?? this.cantidadInsumo,
    );
  }
}

/// Representa una partida individual dentro del ticket
class SaleDetailItem {
  final String id;
  final String productoId;
  final String nombre;
  final String descripcion;
  final double cantidad;
  final double precioHistorico;
  final double costoHistorico;
  final double descuentoLinea;
  final double totalLinea;
  final String? ubicacion;
  final String? sku;
  final String? marca;
  final bool esServicio;
  final String? insumoVinculadoId;
  final double cantidadInsumo;
  final String etiquetaPrecio; // 'Público', 'Cerrajero', 'Taller', 'Mayoreo', 'Manual'
  final double stockDisponible; // Para indicador visual en la tabla de cobro

  SaleDetailItem({
    required this.id,
    required this.productoId,
    String? nombre,
    required this.descripcion,
    required this.cantidad,
    required this.precioHistorico,
    this.costoHistorico = 0.0,
    this.descuentoLinea = 0.0,
    required this.totalLinea,
    this.ubicacion,
    this.sku,
    this.marca,
    this.esServicio = false,
    this.insumoVinculadoId,
    this.cantidadInsumo = 1.0,
    this.etiquetaPrecio = 'Público',
    this.stockDisponible = 0.0,
  }) : nombre = (nombre != null && nombre.isNotEmpty) ? nombre : descripcion;

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
      'nombre': nombre,
      'descripcion': descripcion,
      'cantidad': cantidad,
      'precio_historico': precioHistorico,
      'costo_historico': costoHistorico,
      'descuento_linea': descuentoLinea,
      'total_linea': totalLinea,
      'sku': sku,
      'marca': marca,
      'ubicacion': ubicacion,
      'es_servicio': esServicio ? 1 : 0,
      'insumo_vinculado_id': insumoVinculadoId,
      'cantidad_insumo': cantidadInsumo,
      'etiqueta_precio': etiquetaPrecio,
    };
  }

  SaleDetailItem copyWith({
    String? id,
    String? productoId,
    String? nombre,
    String? descripcion,
    double? cantidad,
    double? precioHistorico,
    double? costoHistorico,
    double? descuentoLinea,
    double? totalLinea,
    String? ubicacion,
    String? sku,
    String? marca,
    bool? esServicio,
    String? insumoVinculadoId,
    double? cantidadInsumo,
    String? etiquetaPrecio,
    double? stockDisponible,
  }) {
    return SaleDetailItem(
      id: id ?? this.id,
      productoId: productoId ?? this.productoId,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      cantidad: cantidad ?? this.cantidad,
      precioHistorico: precioHistorico ?? this.precioHistorico,
      costoHistorico: costoHistorico ?? this.costoHistorico,
      descuentoLinea: descuentoLinea ?? this.descuentoLinea,
      totalLinea: totalLinea ?? this.totalLinea,
      ubicacion: ubicacion ?? this.ubicacion,
      sku: sku ?? this.sku,
      marca: marca ?? this.marca,
      esServicio: esServicio ?? this.esServicio,
      insumoVinculadoId: insumoVinculadoId ?? this.insumoVinculadoId,
      cantidadInsumo: cantidadInsumo ?? this.cantidadInsumo,
      etiquetaPrecio: etiquetaPrecio ?? this.etiquetaPrecio,
      stockDisponible: stockDisponible ?? this.stockDisponible,
    );
  }
}

/// Representa una venta aparcada / en espera con nombre identificador
class HeldSale {
  final String id;
  final String alias;
  final List<SaleDetailItem> items;
  final DateTime heldAt;

  HeldSale({
    required this.id,
    required this.alias,
    required this.items,
    required this.heldAt,
  });
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

/// Cliente extendido para facturación y cuentas por cobrar
class Cliente {
  final String id;
  final String nombre;
  final String? rfcODni;
  final String? regimenFiscal;
  final String? usoCfdi;
  final String? codigoPostal;
  final String? correo;
  final String? telefono;
  final String? direccion;
  final double limiteCredito;
  final double saldoDeudor;
  final String tarifaPreferencial; // 'Público', 'Cerrajero', 'Taller'
  final bool activo;

  Cliente({
    required this.id,
    required this.nombre,
    this.rfcODni,
    this.regimenFiscal,
    this.usoCfdi,
    this.codigoPostal,
    this.correo,
    this.telefono,
    this.direccion,
    required this.limiteCredito,
    required this.saldoDeudor,
    this.tarifaPreferencial = 'Público',
    this.activo = true,
  });

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      rfcODni: map['rfc_o_dni'] as String?,
      regimenFiscal: map['regimen_fiscal'] as String?,
      usoCfdi: map['uso_cfdi'] as String?,
      codigoPostal: map['codigo_postal'] as String?,
      correo: map['correo'] as String?,
      telefono: map['telefono'] as String?,
      direccion: map['direccion'] as String?,
      limiteCredito: (map['limite_credito'] as num?)?.toDouble() ?? 0.0,
      saldoDeudor: (map['saldo_deudor'] as num?)?.toDouble() ?? 0.0,
      tarifaPreferencial: map['tarifa_preferencial'] as String? ?? 'Público',
      activo: (map['activo'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'rfc_o_dni': rfcODni,
      'regimen_fiscal': regimenFiscal,
      'uso_cfdi': usoCfdi,
      'codigo_postal': codigoPostal,
      'correo': correo,
      'telefono': telefono,
      'direccion': direccion,
      'limite_credito': limiteCredito,
      'saldo_deudor': saldoDeudor,
      'tarifa_preferencial': tarifaPreferencial,
      'activo': activo ? 1 : 0,
    };
  }
}

/// Registro del Kardex de Movimientos de Inventario
class InventoryMovementRecord {
  final String id;
  final String productoId;
  final String productoDesc;
  final String tipo; // 'VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION'
  final double cantidad;
  final double stockAnterior;
  final double stockNuevo;
  final String usuarioId;
  final String? departamento;
  final String? motivo;
  final DateTime fecha;

  InventoryMovementRecord({
    required this.id,
    required this.productoId,
    required this.productoDesc,
    required this.tipo,
    required this.cantidad,
    required this.stockAnterior,
    required this.stockNuevo,
    required this.usuarioId,
    this.departamento,
    this.motivo,
    required this.fecha,
  });

  factory InventoryMovementRecord.fromMap(Map<String, dynamic> map) {
    return InventoryMovementRecord(
      id: map['id'] as String,
      productoId: map['producto_id'] as String,
      productoDesc: map['producto_desc'] as String? ?? '',
      tipo: map['tipo'] as String,
      cantidad: (map['cantidad'] as num).toDouble(),
      stockAnterior: (map['stock_anterior'] as num).toDouble(),
      stockNuevo: (map['stock_nuevo'] as num).toDouble(),
      usuarioId: map['usuario_id'] as String? ?? 'cajero',
      departamento: map['departamento'] as String?,
      motivo: map['motivo'] as String?,
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }
}

/// Modelo de Departamento
class DepartmentModel {
  final String id;
  final String nombre;

  DepartmentModel({required this.id, required this.nombre});

  factory DepartmentModel.fromMap(Map<String, dynamic> map) {
    return DepartmentModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
    );
  }
}

/// Modelo de Movimiento de Caja (Entrada / Salida)
class CashMovementRecord {
  final String id;
  final String corteCajaId;
  final String tipo; // 'entrada' o 'salida'
  final double monto;
  final String concepto;
  final DateTime fecha;

  CashMovementRecord({
    required this.id,
    required this.corteCajaId,
    required this.tipo,
    required this.monto,
    required this.concepto,
    required this.fecha,
  });

  factory CashMovementRecord.fromMap(Map<String, dynamic> map) {
    return CashMovementRecord(
      id: map['id'] as String,
      corteCajaId: map['corte_caja_id'] as String,
      tipo: map['tipo'] as String,
      monto: (map['monto'] as num).toDouble(),
      concepto: map['concepto'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
    );
  }
}