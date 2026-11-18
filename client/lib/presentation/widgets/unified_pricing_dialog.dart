import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';

/// Modal Unificado Anti-Saturación para Gestión de Precios por Nivel y Descuentos Porcentuales.
/// 100% Responsivo para Tablets (Touch Targets >= 40px) y Teclado Físico (1, 2, 3, 4, Enter, Esc).
class UnifiedPricingDialog extends StatefulWidget {
  final CartController cartController;
  final SaleDetailItem? item;
  final Product? product;
  final bool isGlobal;

  const UnifiedPricingDialog({
    super.key,
    required this.cartController,
    this.item,
    this.product,
    this.isGlobal = false,
  });

  static Future<void> show({
    required BuildContext context,
    required CartController cartController,
    SaleDetailItem? item,
    Product? product,
    bool isGlobal = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UnifiedPricingDialog(
        cartController: cartController,
        item: item,
        product: product,
        isGlobal: isGlobal,
      ),
    );
  }

  @override
  State<UnifiedPricingDialog> createState() => _UnifiedPricingDialogState();
}

class _UnifiedPricingDialogState extends State<UnifiedPricingDialog> {
  late String _selectedTier;
  double _discountPercent = 0.0;
  final TextEditingController _customDiscountController = TextEditingController();
  final TextEditingController _manualPriceController = TextEditingController();
  final FocusNode _manualPriceFocusNode = FocusNode();
  final FocusNode _customDiscountFocusNode = FocusNode();

  // Ajuste de insumo dinámico si es servicio
  double _insumoQty = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.isGlobal || widget.item == null) {
      _selectedTier = widget.cartController.currentGlobalTier;
    } else {
      final curLabel = widget.item!.etiquetaPrecio;
      if (curLabel.contains('Cerrajero')) {
        _selectedTier = 'Cerrajero';
      } else if (curLabel.contains('Taller')) {
        _selectedTier = 'Taller';
      } else if (curLabel.contains('Mayoreo')) {
        _selectedTier = 'Mayoreo';
      } else if (curLabel.contains('Manual')) {
        _selectedTier = 'Manual';
      } else {
        _selectedTier = 'Público';
      }

      // Detectar descuento preexistente en la línea
      if (widget.item!.descuentoLinea > 0 && widget.item!.cantidad > 0 && widget.item!.precioHistorico > 0) {
        final totalBase = widget.item!.cantidad * widget.item!.precioHistorico;
        _discountPercent = ((widget.item!.descuentoLinea / totalBase) * 100.0).clamp(0.0, 100.0);
        if (_discountPercent > 0) {
          _customDiscountController.text = _discountPercent % 1 == 0
              ? _discountPercent.toStringAsFixed(0)
              : _discountPercent.toStringAsFixed(1);
        }
      }

      _insumoQty = widget.item!.cantidadInsumoConsumida;
      if (_selectedTier == 'Manual') {
        _manualPriceController.text = widget.item!.precioHistorico.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _customDiscountController.dispose();
    _manualPriceController.dispose();
    _manualPriceFocusNode.dispose();
    _customDiscountFocusNode.dispose();
    super.dispose();
  }

  Product _getBaseProduct() {
    if (widget.product != null) return widget.product!;
    if (widget.item != null) {
      final cached = widget.cartController.getProductFromCache(widget.item!.productoId);
      if (cached != null) return cached;
      return Product(
        id: widget.item!.productoId,
        nombre: widget.item!.nombre,
        descripcion: widget.item!.descripcion,
        precioCompra: widget.item!.costoHistorico,
        precioVenta: widget.item!.precioHistorico,
        stockActual: widget.item!.stockDisponible,
      );
    }
    return Product(
      id: 'GLOBAL',
      nombre: 'Venta General',
      descripcion: 'Venta General',
      precioCompra: 0.0,
      precioVenta: 0.0,
      stockActual: 9999.0,
    );
  }

  double _getPriceForTier(String tier) {
    if (widget.isGlobal || widget.item == null) return 0.0;
    final prod = _getBaseProduct();
    switch (tier) {
      case 'Cerrajero':
        return (prod.precioCerrajero != null && prod.precioCerrajero! > 0)
            ? prod.precioCerrajero!
            : prod.precioVenta;
      case 'Taller':
        return (prod.precioTaller != null && prod.precioTaller! > 0)
            ? prod.precioTaller!
            : prod.precioVenta;
      case 'Mayoreo':
        return (prod.precioMayoreo != null && prod.precioMayoreo! > 0)
            ? prod.precioMayoreo!
            : prod.precioVenta;
      case 'Manual':
        final manualVal = double.tryParse(_manualPriceController.text.trim());
        return (manualVal != null && manualVal >= 0) ? manualVal : widget.item!.precioHistorico;
      case 'Público':
      default:
        return prod.precioVenta;
    }
  }

  double get _currentBaseUnitPrice {
    if (_selectedTier == 'Manual') {
      final m = double.tryParse(_manualPriceController.text.trim());
      if (m != null && m >= 0) return m;
      return widget.item?.precioHistorico ?? 0.0;
    }
    return _getPriceForTier(_selectedTier);
  }

  double get _currentEffectiveUnitPrice {
    final base = _currentBaseUnitPrice;
    if (_discountPercent <= 0) return base;
    final discountPerUnit = base * (_discountPercent / 100.0);
    final result = base - discountPerUnit;
    return result < 0 ? 0.0 : result;
  }

  void _applyChanges() {
    if (widget.isGlobal || widget.item == null) {
      widget.cartController.applyGlobalPriceAndDiscount(
        tierLabel: _selectedTier,
        discountPercent: _discountPercent,
      );
    } else {
      widget.cartController.applyItemPriceAndDiscount(
        detailItemId: widget.item!.id,
        newUnitPrice: _currentBaseUnitPrice,
        tierLabel: _selectedTier,
        discountPercent: _discountPercent,
        manualFinalPrice: null,
        newInsumoConsumida: widget.item!.hasDynamicInsumo ? _insumoQty : null,
      );
    }

    Navigator.of(context).pop();
  }

  void _selectTier(String tier) {
    setState(() {
      _selectedTier = tier;
      if (tier != 'Manual') {
        _manualPriceController.clear();
      }
    });
  }

  void _selectDiscount(double pct) {
    setState(() {
      _discountPercent = pct;
      _customDiscountController.text = pct % 1 == 0 ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGlobal = widget.isGlobal || widget.item == null;
    final prod = _getBaseProduct();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _applyChanges,
        const SingleActivator(LogicalKeyboardKey.digit1): () => _selectTier('Público'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _selectTier('Cerrajero'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _selectTier('Taller'),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _selectTier('Mayoreo'),
      },
      child: FocusScope(
        autofocus: true,
        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.all(20),
          title: Row(
            children: [
              Icon(
                isGlobal ? Icons.auto_awesome : Icons.sell_outlined,
                color: const Color(0xFF1F4E79),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGlobal ? 'Precios y Descuento Masivo' : 'Gestor de Precio y Descuento',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                    ),
                    Text(
                      isGlobal
                          ? 'Afectará a los ${widget.cartController.items.length} artículos del ticket actual'
                          : '${widget.item?.nombre ?? prod.nombre} (${widget.item?.cantidad.toStringAsFixed(widget.item!.cantidad % 1 == 0 ? 0 : 2)} pzas)',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // BLOQUE 1: MATRIZ DE NIVELES BASE
                  const Text(
                    '1. Nivel de Precio Base:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF37474F)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTierCard(
                        keyNumber: '1',
                        tier: 'Público',
                        title: 'Público Casual',
                        price: isGlobal ? null : _getPriceForTier('Público'),
                        color: const Color(0xFF2E7D32),
                        icon: Icons.people_outline,
                      ),
                      _buildTierCard(
                        keyNumber: '2',
                        tier: 'Cerrajero',
                        title: 'Colega Cerrajero',
                        price: isGlobal ? null : _getPriceForTier('Cerrajero'),
                        color: const Color(0xFF0D47A1),
                        icon: Icons.vpn_key_outlined,
                      ),
                      _buildTierCard(
                        keyNumber: '3',
                        tier: 'Taller',
                        title: 'Taller / Especial',
                        price: isGlobal ? null : _getPriceForTier('Taller'),
                        color: const Color(0xFF4A148C),
                        icon: Icons.build_outlined,
                      ),
                      _buildTierCard(
                        keyNumber: '4',
                        tier: 'Mayoreo',
                        title: 'Mayoreo Volumen',
                        price: isGlobal ? null : _getPriceForTier('Mayoreo'),
                        color: const Color(0xFFE65100),
                        icon: Icons.layers_outlined,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // BLOQUE 2: SELECTOR RÁPIDO DE DESCUENTO %
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2. Descuento Porcentual (%):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF37474F)),
                      ),
                      if (_discountPercent > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            '-${_discountPercent % 1 == 0 ? _discountPercent.toStringAsFixed(0) : _discountPercent.toStringAsFixed(1)}% aplicado',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildDiscountChip(0.0, '0%'),
                      const SizedBox(width: 6),
                      _buildDiscountChip(5.0, '-5%'),
                      const SizedBox(width: 6),
                      _buildDiscountChip(10.0, '-10%'),
                      const SizedBox(width: 6),
                      _buildDiscountChip(15.0, '-15%'),
                      const SizedBox(width: 6),
                      _buildDiscountChip(20.0, '-20%'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _customDiscountController,
                          focusNode: _customDiscountFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '% manual',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val.trim()) ?? 0.0;
                            setState(() {
                              _discountPercent = parsed.clamp(0.0, 100.0);
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // BLOQUE 3: RESUMEN DINÁMICO EN TIEMPO REAL Y EDICIÓN MANUAL
                  if (!isGlobal && widget.item != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Precio Base ($_selectedTier):',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                              ),
                              Text(
                                '\$${_currentBaseUnitPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  decoration: _discountPercent > 0 ? TextDecoration.lineThrough : null,
                                  color: _discountPercent > 0 ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          if (_discountPercent > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Ahorro Descuento (-${_discountPercent % 1 == 0 ? _discountPercent.toStringAsFixed(0) : _discountPercent.toStringAsFixed(1)}%):',
                                  style: TextStyle(fontSize: 13, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '-\$${(_currentBaseUnitPrice * (_discountPercent / 100.0)).toStringAsFixed(2)} / pza',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),
                          const Divider(height: 1),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PRECIO FINAL UNITARIO:',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                              ),
                              Text(
                                '\$${_currentEffectiveUnitPrice.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Línea (${widget.item!.cantidad.toStringAsFixed(widget.item!.cantidad % 1 == 0 ? 0 : 2)} pzas):',
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              Text(
                                '\$${(_currentEffectiveUnitPrice * widget.item!.cantidad).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Opción: Escribir precio base manual en $ (sincronizado con descuentos)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualPriceController,
                            focusNode: _manualPriceFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Precio manual:',
                              hintText: 'Ingrese precio base (ej. 10.00)',
                              prefixText: r'$ ',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (val) {
                              final p = double.tryParse(val.trim());
                              if (p != null && p >= 0) {
                                setState(() {
                                  _selectedTier = 'Manual';
                                  // Mantiene el descuento actual activo para recalcular en vivo
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    // Si es servicio con insumo vinculado, botón discreto para ajustar consumo físico
                    if (widget.item!.hasDynamicInsumo) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F7FA),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF80DEEA)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '🔧 Insumo ocupado: ${_insumoQty.toStringAsFixed(_insumoQty % 1 == 0 ? 0 : 2)} pza (${widget.item!.insumoUtilizadoNombre ?? ''})',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF006064)),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20, color: Color(0xFF006064)),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    final nxt = (_insumoQty - 1.0) < 0 ? 0.0 : (_insumoQty - 1.0);
                                    setState(() => _insumoQty = nxt);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF006064)),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() => _insumoQty += 1.0);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    // Resumen Global
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        'Se aplicará el nivel [$_selectedTier] con ${_discountPercent > 0 ? "-$_discountPercent% de descuento" : "sin descuento adicional"} a cada uno de los productos y servicios del carrito.',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar [Esc]'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                isGlobal ? 'Aplicar a Todo el Ticket [Enter]' : 'Aplicar Precio [Enter]',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _applyChanges,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard({
    required String keyNumber,
    required String tier,
    required String title,
    double? price,
    required Color color,
    required IconData icon,
  }) {
    final isSelected = _selectedTier == tier;

    return Material(
      color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _selectTier(tier),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : Colors.blueGrey.shade200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  keyNumber,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? color : Colors.black87,
                      ),
                    ),
                    if (price != null)
                      Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : const Color(0xFF2E7D32),
                        ),
                      ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, size: 18, color: color)
              else
                Icon(icon, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscountChip(double pct, String label) {
    final isSelected = (_discountPercent == pct);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: Colors.red.shade100,
      labelStyle: TextStyle(color: isSelected ? Colors.red.shade900 : Colors.black87),
      side: BorderSide(color: isSelected ? Colors.red.shade400 : Colors.grey.shade300),
      onSelected: (_) => _selectDiscount(pct),
    );
  }
}
