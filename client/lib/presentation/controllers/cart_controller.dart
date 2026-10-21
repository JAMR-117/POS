import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/local/models.dart';
import '../../data/repositories/sales_repository.dart';

/// Gestor reactivo de estado para el punto de cobro (POS Especializado en Cerrajería)
class CartController extends ChangeNotifier {
  final SalesRepository _salesRepository;

  CartController({SalesRepository? salesRepository})
      : _salesRepository = salesRepository ?? SalesRepository();

  // ---------------------------------------------------------------------------
  // ESTADO EN MEMORIA
  // ---------------------------------------------------------------------------
  final List<SaleDetailItem> _items = [];
  final List<HeldSale> _heldSales = [];
  final Map<String, Product> _productCache = {};

  bool _isLoading = false;
  String? _errorMessage;

  String _selectedClientId = 'PUBLICO-GRAL';
  String _selectedClientName = 'Público en General';
  String _selectedClientTier = 'Público'; // 'Público', 'Cerrajero', 'Taller'
  String _currentGlobalTier = 'Público';

  SalesRepository get salesRepository => _salesRepository;

  // Getters reactivos
  List<SaleDetailItem> get items => List.unmodifiable(_items);
  List<HeldSale> get heldSales => List.unmodifiable(_heldSales);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _items.isEmpty;
  String get selectedClientId => _selectedClientId;
  String get selectedClientName => _selectedClientName;
  String get selectedClientTier => _selectedClientTier;
  String get currentGlobalTier => _currentGlobalTier;
  int get heldSalesCount => _heldSales.length;

  Product? getProductFromCache(String id) => _productCache[id];

  void cacheProduct(Product product) {
    _productCache[product.id] = product;
  }

  /// Obtiene el stock físico o capacidad efectiva disponible para un producto o servicio.
  Future<double> getEffectiveStockForProduct(Product product) async {
    _productCache[product.id] = product;
    if (product.esServicio) {
      if (product.insumoVinculadoId == null || product.insumoVinculadoId!.trim().isEmpty) {
        return double.infinity;
      }
      final insumoId = product.insumoVinculadoId!.trim();
      Product? insumo = _productCache[insumoId];
      if (insumo == null) {
        insumo = await _salesRepository.findProductById(insumoId);
        if (insumo != null) _productCache[insumoId] = insumo;
      }
      if (insumo != null) {
        final cantInsumo = (product.cantidadInsumo > 0)
            ? product.cantidadInsumo
            : 1.0;
        return insumo.stockActual / cantInsumo;
      }
      return double.infinity;
    }
    return product.stockActual;
  }

  /// Retorna la cantidad ya apartada en el carrito para un producto o insumo vinculado.
  double getReservedQuantityInCart(String productId) {
    double total = 0.0;
    for (final item in _items) {
      if (item.productoId == productId) {
        total += item.cantidad;
      } else if (item.esServicio && item.insumoVinculadoId == productId) {
        final factor = (item.cantidadInsumo > 0) ? item.cantidadInsumo : 1.0;
        total += item.cantidad * factor;
      }
    }
    return total;
  }

  void setClient(String id, String name, {String tier = 'Público'}) {
    _selectedClientId = id;
    _selectedClientName = name;
    _selectedClientTier = tier;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // CÁLCULOS AUTOMÁTICOS EN TIEMPO REAL (LATENCIA CERO)
  // ---------------------------------------------------------------------------

  double get subtotal => _items.fold(
        0.0,
        (acc, item) => acc + (item.cantidad * item.precioHistorico),
      );

  double get descuentoTotal => _items.fold(
        0.0,
        (acc, item) => acc + item.descuentoLinea,
      );

  double get total => _items.fold(
        0.0,
        (acc, item) => acc + item.totalLinea,
      );

  double get impuestosTotal => 0.0;

  // ---------------------------------------------------------------------------
  // LÓGICA DE PRECIOS MULTI-NIVEL Y MAYOREO
  // ---------------------------------------------------------------------------

  double _determineApplicablePrice(Product product, double currentQuantity, {String? targetTier}) {
    final tier = targetTier ?? _selectedClientTier;

    // Si alcanza mayoreo por volumen
    if (product.hasWholesalePrice && currentQuantity >= product.cantidadMayoreo!) {
      return product.precioMayoreo!;
    }

    if (tier == 'Cerrajero' && product.precioCerrajero != null && product.precioCerrajero! > 0) {
      return product.precioCerrajero!;
    }

    if (tier == 'Taller' && product.precioTaller != null && product.precioTaller! > 0) {
      return product.precioTaller!;
    }

    return product.precioVenta;
  }

  String _determineApplicableTierLabel(Product product, double currentQuantity, {String? targetTier}) {
    final tier = targetTier ?? _selectedClientTier;

    if (product.hasWholesalePrice && currentQuantity >= product.cantidadMayoreo!) {
      return 'Mayoreo';
    }
    if (tier == 'Cerrajero' && product.precioCerrajero != null && product.precioCerrajero! > 0) {
      return 'Cerrajero';
    }
    if (tier == 'Taller' && product.precioTaller != null && product.precioTaller! > 0) {
      return 'Taller';
    }
    return 'Público';
  }

  // ---------------------------------------------------------------------------
  // MUTACIONES DEL TICKET ACTIVO
  // ---------------------------------------------------------------------------

  void addProduct(Product product, {double quantity = 1.0, String? preferredTier}) {
    if (quantity <= 0) return;

    _productCache[product.id] = product;

    final existingIndex = _items.indexWhere((item) => item.productoId == product.id);

    if (existingIndex != -1) {
      final current = _items[existingIndex];
      final double newQuantity = (product.esAGranel || product.esServicio)
          ? (current.cantidad + quantity)
          : (current.cantidad + 1.0);

      final String tierLabel = preferredTier ?? current.etiquetaPrecio;
      final double applicablePrice = _determineApplicablePrice(product, newQuantity, targetTier: tierLabel);
      final double newTotal = _calculateLineTotal(
        newQuantity,
        applicablePrice,
        current.descuentoLinea,
      );

      _items[existingIndex] = current.copyWith(
        cantidad: _roundToDecimals(newQuantity, 3),
        precioHistorico: applicablePrice,
        totalLinea: _roundToDecimals(newTotal, 2),
        etiquetaPrecio: _determineApplicableTierLabel(product, newQuantity, targetTier: tierLabel),
        stockDisponible: product.stockActual,
      );
    } else {
      final String tierLabel = preferredTier ?? _selectedClientTier;
      final double applicablePrice = _determineApplicablePrice(product, quantity, targetTier: tierLabel);
      final double totalLinea = _calculateLineTotal(quantity, applicablePrice, 0.0);

      _items.add(
        SaleDetailItem(
          id: _generateLocalUUID(),
          productoId: product.id,
          nombre: product.nombre,
          descripcion: product.descripcion,
          cantidad: _roundToDecimals(quantity, 3),
          precioHistorico: applicablePrice,
          costoHistorico: product.precioCompra,
          descuentoLinea: 0.0,
          totalLinea: _roundToDecimals(totalLinea, 2),
          ubicacion: product.ubicacion,
          sku: product.sku,
          marca: product.marca,
          esServicio: product.esServicio,
          insumoVinculadoId: product.insumoVinculadoId,
          cantidadInsumo: product.cantidadInsumo,
          etiquetaPrecio: _determineApplicableTierLabel(product, quantity, targetTier: tierLabel),
          stockDisponible: product.stockActual,
        ),
      );
    }

    _clearError();
    notifyListeners();
  }

  /// Cambia el nivel de precio de una partida específica (Público, Cerrajero, Taller, Mayoreo, Manual)
  void changeItemPriceTier(String detailItemId, double newPrice, String tierLabel) {
    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1 || newPrice < 0) return;

    final current = _items[index];
    final double totalLinea = _calculateLineTotal(current.cantidad, newPrice, current.descuentoLinea);

    _items[index] = current.copyWith(
      precioHistorico: newPrice,
      etiquetaPrecio: tierLabel,
      totalLinea: _roundToDecimals(totalLinea, 2),
    );

    notifyListeners();
  }

  /// Aplica un nivel de precio global a todos los productos del ticket con fallback estricto a precio público
  void applyGlobalPriceTier(String tierLabel) {
    _currentGlobalTier = tierLabel;

    for (int i = 0; i < _items.length; i++) {
      final current = _items[i];
      final product = _productCache[current.productoId];

      double applicablePrice = current.precioHistorico;
      String appliedLabel = 'Público';

      if (product != null) {
        if (tierLabel == 'Cerrajero') {
          if (product.precioCerrajero != null && product.precioCerrajero! > 0) {
            applicablePrice = product.precioCerrajero!;
            appliedLabel = 'Cerrajero';
          } else {
            applicablePrice = product.precioVenta;
            appliedLabel = 'Público';
          }
        } else if (tierLabel == 'Taller') {
          if (product.precioTaller != null && product.precioTaller! > 0) {
            applicablePrice = product.precioTaller!;
            appliedLabel = 'Taller';
          } else {
            applicablePrice = product.precioVenta;
            appliedLabel = 'Público';
          }
        } else if (tierLabel == 'Mayoreo') {
          if (product.precioMayoreo != null && product.precioMayoreo! > 0) {
            applicablePrice = product.precioMayoreo!;
            appliedLabel = 'Mayoreo';
          } else {
            applicablePrice = product.precioVenta;
            appliedLabel = 'Público';
          }
        } else {
          // 'Público' o por defecto
          applicablePrice = product.precioVenta;
          appliedLabel = 'Público';
        }
      } else {
        if (tierLabel == 'Público') {
          appliedLabel = 'Público';
        }
      }

      final double totalLinea = _calculateLineTotal(
        current.cantidad,
        applicablePrice,
        current.descuentoLinea,
      );

      _items[i] = current.copyWith(
        precioHistorico: applicablePrice,
        etiquetaPrecio: appliedLabel,
        totalLinea: _roundToDecimals(totalLinea, 2),
      );
    }

    notifyListeners();
  }

  /// Actualiza la cantidad exacta y recalcula mayoreo
  void updateQuantity(String detailItemId, double newQuantity, {Product? referenceProduct}) {
    if (newQuantity <= 0) {
      removeItem(detailItemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1) return;

    final current = _items[index];
    final prod = referenceProduct ?? _productCache[current.productoId];

    double applicablePrice = current.precioHistorico;
    String tierLabel = current.etiquetaPrecio;

    if (prod != null && current.etiquetaPrecio != 'Manual') {
      applicablePrice = _determineApplicablePrice(prod, newQuantity, targetTier: current.etiquetaPrecio);
      tierLabel = _determineApplicableTierLabel(prod, newQuantity, targetTier: current.etiquetaPrecio);
    }

    final double totalLinea = _calculateLineTotal(
      newQuantity,
      applicablePrice,
      current.descuentoLinea,
    );

    _items[index] = current.copyWith(
      cantidad: _roundToDecimals(newQuantity, 3),
      precioHistorico: applicablePrice,
      etiquetaPrecio: tierLabel,
      totalLinea: _roundToDecimals(totalLinea, 2),
    );

    notifyListeners();
  }

  void incrementQuantity(String detailItemId, {Product? referenceProduct}) {
    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1) return;
    updateQuantity(detailItemId, _items[index].cantidad + 1.0, referenceProduct: referenceProduct);
  }

  void decrementQuantity(String detailItemId, {Product? referenceProduct}) {
    final index = _items.indexWhere((item) => item.id == detailItemId);
    if (index == -1) return;
    final currentQty = _items[index].cantidad;
    if (currentQty <= 1.0) {
      removeItem(detailItemId);
    } else {
      updateQuantity(detailItemId, currentQty - 1.0, referenceProduct: referenceProduct);
    }
  }

  void incrementLastItem() {
    if (_items.isNotEmpty) {
      incrementQuantity(_items.last.id);
    }
  }

  void decrementLastItem() {
    if (_items.isNotEmpty) {
      decrementQuantity(_items.last.id);
    }
  }

  void addCommonArticle(double amount, {String description = 'Artículo Común'}) {
    if (amount <= 0) return;

    final desc = description.trim().isEmpty ? 'Artículo Común' : description.trim();
    _items.add(
      SaleDetailItem(
        id: _generateLocalUUID(),
        productoId: 'ART-COMUN',
        nombre: desc,
        descripcion: desc,
        cantidad: 1.0,
        precioHistorico: amount,
        costoHistorico: 0.0,
        descuentoLinea: 0.0,
        totalLinea: _roundToDecimals(amount, 2),
        ubicacion: 'Caja',
        sku: 'ART-COMUN',
        marca: 'Genérica',
        etiquetaPrecio: 'Manual',
        stockDisponible: 9999.0,
      ),
    );
    notifyListeners();
  }

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

    _items[index] = current.copyWith(
      descuentoLinea: _roundToDecimals(safeDiscount, 2),
      totalLinea: _roundToDecimals(totalLinea, 2),
    );

    notifyListeners();
  }

  void removeItem(String detailItemId) {
    _items.removeWhere((item) => item.id == detailItemId);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _selectedClientId = 'PUBLICO-GRAL';
    _selectedClientName = 'Público en General';
    _selectedClientTier = 'Público';
    _currentGlobalTier = 'Público';
    _clearError();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // INTEGRACIÓN CON REPOSITORIO LOCAL (ESCANEO Y CHECKOUT)
  // ---------------------------------------------------------------------------

  Future<List<Product>> scanOrSearchProduct(String input, {double defaultWeight = 1.0}) async {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return [];

    _setLoading(true);
    try {
      final exactMatch = await _salesRepository.findProductByBarcodeOrSku(cleanInput);
      if (exactMatch != null) {
        _productCache[exactMatch.id] = exactMatch;
        _setLoading(false);
        return [exactMatch];
      }

      final matches = await _salesRepository.searchProductsAdvanced(cleanInput);
      _setLoading(false);
      return matches;
    } catch (e) {
      _setError('Error al consultar catálogo: $e');
      _setLoading(false);
      return [];
    }
  }

  Future<double> checkout({
    required List<PaymentMethodBreakdown> pagos,
    required String corteCajaId,
    String? folioTicket,
    double? totalRecibidoEfectivo,
  }) async {
    if (_items.isEmpty) {
      throw Exception('El carrito está vacío');
    }

    final double totalVenta = total;
    final double totalPagado = totalRecibidoEfectivo != null
        ? (pagos.where((p) => p.metodo != 'efectivo').fold(0.0, (acc, p) => acc + p.monto) + totalRecibidoEfectivo)
        : pagos.fold(0.0, (acc, p) => acc + p.monto);

    if (_roundToDecimals(totalPagado, 2) < _roundToDecimals(totalVenta, 2)) {
      final faltante = _roundToDecimals(totalVenta - totalPagado, 2);
      throw Exception('Pago insuficiente. Monto faltante: $faltante');
    }

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

      await _salesRepository.processSaleTransaction(request);

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
  // MANEJO DE VENTAS EN ESPERA (HOLD / RESUME) CON ALIAS PERSONALIZADO
  // ---------------------------------------------------------------------------

  bool holdCurrentSale({String? alias}) {
    if (_items.isEmpty) return false;

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final customAlias = (alias != null && alias.trim().isNotEmpty)
        ? alias.trim()
        : 'Ticket #${_heldSales.length + 1} ($timeStr)';

    _heldSales.add(
      HeldSale(
        id: _generateLocalUUID(),
        alias: customAlias,
        items: List.from(_items),
        heldAt: now,
      ),
    );

    _items.clear();
    _clearError();
    notifyListeners();
    return true;
  }

  bool resumeSale(int index) {
    if (index < 0 || index >= _heldSales.length) return false;

    if (_items.isNotEmpty) {
      holdCurrentSale();
    }

    final resumed = _heldSales.removeAt(index);
    _items.addAll(resumed.items);
    _clearError();
    notifyListeners();
    return true;
  }

  void discardHeldSale(int index) {
    if (index >= 0 && index < _heldSales.length) {
      _heldSales.removeAt(index);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // UTILIDADES PRIVADAS
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
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-${hex.sublist(10, 16).join()}';
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