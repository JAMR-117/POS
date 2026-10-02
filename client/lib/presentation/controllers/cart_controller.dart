import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/local/models.dart';
import '../../data/repositories/sales_repository.dart';

/// Representa una venta aparcada / en espera
class HeldSale {
  final String id;
  final List<SaleDetailItem> items;
  final DateTime heldAt;

  HeldSale({
    required this.id,
    required this.items,
    required this.heldAt,
  });
}

/// Gestor reactivo de estado para el punto de cobro (Fase 2: Core UI)
class CartController extends ChangeNotifier {
  final SalesRepository _salesRepository;

  CartController({SalesRepository? salesRepository})
      : _salesRepository = salesRepository ?? SalesRepository();

  // ---------------------------------------------------------------------------
  // ESTADO EN MEMORIA
  // ---------------------------------------------------------------------------
  final List<SaleDetailItem> _items = [];
  final List<HeldSale> _heldSales = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters reactivos inmutables
  List<SaleDetailItem> get items => List.unmodifiable(_items);
  List<HeldSale> get heldSales => List.unmodifiable(_heldSales);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _items.isEmpty;

  // ---------------------------------------------------------------------------
  // CÁLCULOS AUTOMÁTICOS EN TIEMPO REAL (LATENCIA CERO)
  // ---------------------------------------------------------------------------

  /// Suma bruta de todas las líneas: (cantidad * precio_historico)
  double get subtotal => _items.fold(
        0.0,
        (acc, item) => acc + (item.cantidad * item.precioHistorico),
      );

  /// Suma consolidada de descuentos aplicados a nivel de partida
  double get descuentoTotal => _items.fold(
        0.0,
        (acc, item) => acc + item.descuentoLinea,
      );

  /// Total neto directo a pagar
  double get total => _items.fold(
        0.0,
        (acc, item) => acc + item.totalLinea,
      );

  /// Impuestos estimados incluidos o desglosados en el total
  /// Nota: Si se requiere base imponible exacta por tasa, se computa por item.
  double get impuestosTotal => 0.0;

  // ---------------------------------------------------------------------------
  // MUTACIONES DEL TICKET ACTIVO
  // ---------------------------------------------------------------------------

  /// Agrega un producto al carrito.
  /// Si existe y no es a granel, incrementa cantidad en 1.
  /// Si es a granel, acumula la cantidad decimal especificada.


  /// Lógica central para calcular el precio dinámico basado en la cantidad
  double _determineApplicablePrice(Product product, double currentQuantity) {
    if (product.cantidadMayoreo != null && 
        product.precioMayoreo != null && 
        product.cantidadMayoreo! > 0 && 
        currentQuantity >= product.cantidadMayoreo!) {
      return product.precioMayoreo!;
    }
    return product.precioVenta;
  }

  /// Agrega un producto al carrito evaluando automáticamente reglas de Mayoreo.
  void addProduct(Product product, {double quantity = 1.0}) {
    if (quantity <= 0) return;

    final existingIndex = _items.indexWhere((item) => item.productoId == product.id);

    if (existingIndex != -1) {
      final current = _items[existingIndex];
      final double newQuantity = product.esAGranel 
          ? (current.cantidad + quantity) 
          : (current.cantidad + 1.0);

      // Reevaluación de precio por volumen (Mayoreo)
      final double applicablePrice = _determineApplicablePrice(product, newQuantity);

      final double newTotal = _calculateLineTotal(
        newQuantity, 
        applicablePrice, 
        current.descuentoLinea,
      );

      _items[existingIndex] = SaleDetailItem(
        id: current.id,
        productoId: current.productoId,
        descripcion: current.descripcion,
        cantidad: _roundToDecimals(newQuantity, 3),
        precioHistorico: applicablePrice, // Se actualiza si cruzó el umbral
        costoHistorico: current.costoHistorico,
        descuentoLinea: current.descuentoLinea,
        totalLinea: _roundToDecimals(newTotal, 2),
      );
    } else {
      final double applicablePrice = _determineApplicablePrice(product, quantity);
      final double totalLinea = _calculateLineTotal(
        quantity, 
        applicablePrice, 
        0.0,
      );

      _items.add(
        SaleDetailItem(
          id: _generateLocalUUID(),
          productoId: product.id,
          descripcion: product.descripcion,
          cantidad: _roundToDecimals(quantity, 3),
          precioHistorico: applicablePrice,
          costoHistorico: product.precioCompra,
          descuentoLinea: 0.0,
          totalLinea: _roundToDecimals(totalLinea, 2),
        ),
      );
    }

    _clearError();
    notifyListeners();
  }

  /// Actualiza la cantidad y recalcula la regla de mayoreo
  void updateQuantity(String detailItemId, double newQuantity, {Product? referenceProduct}) {
    if (newQuantity <= 0) {
      removeItem(detailItemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1) return;

    final current = _items[index];
    
    // Si se pasa la referencia original del producto, reevalúa el mayoreo
    double applicablePrice = current.precioHistorico;
    if (referenceProduct != null) {
       applicablePrice = _determineApplicablePrice(referenceProduct, newQuantity);
    }

    final double totalLinea = _calculateLineTotal(
      newQuantity, 
      applicablePrice, 
      current.descuentoLinea,
    );

    _items[index] = SaleDetailItem(
      id: current.id,
      productoId: current.productoId,
      descripcion: current.descripcion,
      cantidad: _roundToDecimals(newQuantity, 3),
      precioHistorico: applicablePrice,
      costoHistorico: current.costoHistorico,
      descuentoLinea: current.descuentoLinea,
      totalLinea: _roundToDecimals(totalLinea, 2),
    );

    notifyListeners();
  }

  /// Agrega un artículo rápido que no existe en el catálogo
  void addCommonArticle(double amount, {String description = 'Artículo Común'}) {
    if (amount <= 0) return;
    
    _items.add(
      SaleDetailItem(
        id: _generateLocalUUID(),
        productoId: 'ART-COMUN', // ID reservado para no afectar inventario
        descripcion: description.isEmpty ? 'Artículo Común' : description,
        cantidad: 1.0,
        precioHistorico: amount,
        costoHistorico: 0.0,
        descuentoLinea: 0.0,
        totalLinea: _roundToDecimals(amount, 2),
      ),
    );
    notifyListeners();
  }

  /// Aplica un descuento en moneda fija a una partida específica
  void applyLineDiscount(String detailItemId, double discountAmount) {
    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1) return;

    final current = _items[index];
    final double maxDiscount = current.cantidad * current.precioHistorico;
    final double safeDiscount = discountAmount.clamp(0.0, maxDiscount);

    final double totalLinea = _calculateLineTotal(
      current.cantidad, 
      current.precioHistorico, 
      safeDiscount,
    );

    _items[index] = SaleDetailItem(
      id: current.id,
      productoId: current.productoId,
      descripcion: current.descripcion,
      cantidad: current.cantidad,
      precioHistorico: current.precioHistorico,
      costoHistorico: current.costoHistorico,
      descuentoLinea: _roundToDecimals(safeDiscount, 2),
      totalLinea: _roundToDecimals(totalLinea, 2),
    );

    notifyListeners();
  }

  /// Elimina una línea individual del carrito
  void removeItem(String detailItemId) {
    _items.removeWhere((item) => item.id == detailItemId);
    notifyListeners();
  }

  /// Limpia todo el ticket activo en milisegundos
  void clearCart() {
    _items.clear();
    _clearError();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // INTEGRACIÓN CON REPOSITORIO LOCAL (ESCANEO Y CHECKOUT)
  // ---------------------------------------------------------------------------

  /// Escanea o busca un producto.
  /// 1. Intenta coincidencia exacta por código/SKU. Si lo halla, lo añade directo.
  /// 2. Si no, busca de forma incremental por descripción y retorna la lista.
  Future<List<Product>> scanOrSearchProduct(String input, {double defaultWeight = 1.0}) async {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return [];

    _setLoading(true);
    try {
      // Intento 1: Coincidencia exacta indexada (lector de barras / SKU)
      final exactMatch = await _salesRepository.findProductByBarcodeOrSku(cleanInput);
      if (exactMatch != null) {
        addProduct(exactMatch, quantity: defaultWeight);
        _setLoading(false);
        return [exactMatch];
      }

      // Intento 2: Búsqueda incremental por descripción
      final matches = await _salesRepository.searchProductsByDescription(cleanInput);
      _setLoading(false);
      return matches;
    } catch (e) {
      _setError('Error al consultar catálogo: $e');
      _setLoading(false);
      return [];
    }
  }

  /// Valida pagos, registra la venta en SQLite atómicamente y limpia el estado
  Future<double> checkout({
    required List<PaymentMethodBreakdown> pagos,
    required String corteCajaId,
    String? folioTicket,
  }) async {
    if (_items.isEmpty) {
      throw Exception('El carrito está vacío');
    }

    final double totalVenta = total;
    final double totalPagado = pagos.fold(0.0, (acc, p) => acc + p.monto);

    // Validación de suficiencia financiera
    if (_roundToDecimals(totalPagado, 2) < _roundToDecimals(totalVenta, 2)) {
      final faltante = _roundToDecimals(totalVenta - totalPagado, 2);
      throw Exception('Pago insuficiente. Monto faltante: $faltante');
    }

    // Cálculo de cambio (asociado a partidas en efectivo)
    final double cambio = _roundToDecimals(totalPagado - totalVenta, 2);

    _setLoading(true);
    try {
      final request = SaleTransactionRequest(
        ventaId: _generateLocalUUID(),
        corteCajaId: corteCajaId,
        folioTicket: folioTicket,
        subtotal: subtotal,
        descuentoTotal: descuentoTotal,
        impuestosTotal: impuestosTotal,
        total: totalVenta,
        pagosDesglose: pagos,
        items: List.from(_items),
        fechaVenta: DateTime.now().toUtc(),
      );

      // Ejecución de la transacción ACID en SQLite + Outbox Pattern
      await _salesRepository.processSaleTransaction(request);

      // Limpieza instantánea para el siguiente cliente
      _items.clear();
      _clearError();
      _setLoading(false);
      notifyListeners();

      return cambio;
    } catch (e) {
      _setError('Fallo transaccional al procesar cobro: $e');
      _setLoading(false);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // MANEJO DE VENTAS EN ESPERA (HOLD / RESUME)
  // ---------------------------------------------------------------------------

  /// Suspende el ticket activo actual y deja la caja limpia
  bool holdCurrentSale() {
    if (_items.isEmpty) return false;

    _heldSales.add(
      HeldSale(
        id: _generateLocalUUID(),
        items: List.from(_items),
        heldAt: DateTime.now(),
      ),
    );

    _items.clear();
    _clearError();
    notifyListeners();
    return true;
  }

  /// Restaura una venta en espera sustituyendo o agregando al ticket actual
  bool resumeSale(int index) {
    if (index < 0 || index >= _heldSales.length) return false;

    // Si hay artículos actuales en pantalla, no se sobreescriben accidentalmente
    if (_items.isNotEmpty) {
      holdCurrentSale();
    }

    final resumed = _heldSales.removeAt(index);
    _items.addAll(resumed.items);
    _clearError();
    notifyListeners();
    return true;
  }

  /// Cancela o descarta un ticket en espera
  void discardHeldSale(int index) {
    if (index >= 0 && index < _heldSales.length) {
      _heldSales.removeAt(index);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // UTILIDADES PRIVADAS DE ALTO RENDIMIENTO
  // ---------------------------------------------------------------------------

  double _calculateLineTotal(double qty, double price, double discount) {
    final raw = (qty * price) - discount;
    return raw < 0.0 ? 0.0 : raw;
  }

  double _roundToDecimals(double val, int places) {
    final mod = pow(10.0, places);
    return ((val * mod).round().toDouble() / mod);
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String msg) {
    _errorMessage = msg;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}