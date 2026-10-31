import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';
import 'insufficient_stock_dialog.dart';

class EditServiceLineDialog extends StatefulWidget {
  final SaleDetailItem item;
  final CartController cartController;

  const EditServiceLineDialog({
    super.key,
    required this.item,
    required this.cartController,
  });

  static Future<bool?> show({
    required BuildContext context,
    required SaleDetailItem item,
    required CartController cartController,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EditServiceLineDialog(
        item: item,
        cartController: cartController,
      ),
    );
  }

  @override
  State<EditServiceLineDialog> createState() => _EditServiceLineDialogState();
}

class _EditServiceLineDialogState extends State<EditServiceLineDialog> {
  late TextEditingController _priceCtrl;
  late TextEditingController _serviceQtyCtrl;
  late TextEditingController _insumoQtyCtrl;

  late double _currentPrice;
  late double _currentServiceQty;
  late double _currentInsumoQty;
  String _currentTier = 'Manual';

  Product? _serviceProduct;
  Product? _insumoProduct;

  @override
  void initState() {
    super.initState();
    _currentPrice = widget.item.precioHistorico;
    _currentServiceQty = widget.item.cantidad;
    _currentInsumoQty = widget.item.cantidadInsumoConsumida;
    _currentTier = widget.item.etiquetaPrecio;

    _priceCtrl = TextEditingController(text: _currentPrice.toStringAsFixed(2));
    _serviceQtyCtrl = TextEditingController(
      text: _currentServiceQty % 1 == 0
          ? _currentServiceQty.toStringAsFixed(0)
          : _currentServiceQty.toStringAsFixed(2),
    );
    _insumoQtyCtrl = TextEditingController(
      text: _currentInsumoQty % 1 == 0
          ? _currentInsumoQty.toStringAsFixed(0)
          : _currentInsumoQty.toStringAsFixed(2),
    );

    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final sRepo = widget.cartController.salesRepository;
    _serviceProduct = widget.cartController.getProductFromCache(widget.item.productoId) ??
        await sRepo.findProductById(widget.item.productoId);

    if (widget.item.hasDynamicInsumo && widget.item.insumoUtilizadoId != null) {
      final insumoId = widget.item.insumoUtilizadoId!;
      _insumoProduct = widget.cartController.getProductFromCache(insumoId) ??
          await sRepo.findProductById(insumoId);
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _serviceQtyCtrl.dispose();
    _insumoQtyCtrl.dispose();
    super.dispose();
  }

  void _onPriceChanged(String val) {
    final p = double.tryParse(val.replaceAll(r'$', '').trim());
    if (p != null && p >= 0) {
      setState(() {
        _currentPrice = p;
        _currentTier = 'Manual';
      });
    }
  }

  void _onServiceQtyChanged(String val) {
    final q = double.tryParse(val.trim());
    if (q != null && q > 0) {
      setState(() => _currentServiceQty = q);
    }
  }

  void _onInsumoQtyChanged(String val) {
    final q = double.tryParse(val.trim());
    if (q != null && q >= 0) {
      setState(() => _currentInsumoQty = q);
    }
  }

  void _adjustServiceQty(double delta) {
    final newQty = max(1.0, _currentServiceQty + delta);
    setState(() {
      _currentServiceQty = newQty;
      _serviceQtyCtrl.text = newQty % 1 == 0 ? newQty.toStringAsFixed(0) : newQty.toStringAsFixed(2);
    });
  }

  void _adjustInsumoQty(double delta) {
    final newQty = max(0.0, _currentInsumoQty + delta);
    setState(() {
      _currentInsumoQty = newQty;
      _insumoQtyCtrl.text = newQty % 1 == 0 ? newQty.toStringAsFixed(0) : newQty.toStringAsFixed(2);
    });
  }

  void _selectSuggestedPrice(double price, String tier) {
    setState(() {
      _currentPrice = price;
      _currentTier = tier;
      _priceCtrl.text = price.toStringAsFixed(2);
    });
  }

  Future<void> _handleConfirm() async {
    final newPrice = double.tryParse(_priceCtrl.text.replaceAll(r'$', '').trim()) ?? _currentPrice;
    final newServiceQty = double.tryParse(_serviceQtyCtrl.text.trim()) ?? _currentServiceQty;
    double newInsumoQty = double.tryParse(_insumoQtyCtrl.text.trim()) ?? _currentInsumoQty;

    if (newPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El precio del servicio no puede ser negativo.')),
      );
      return;
    }

    if (newServiceQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cantidad de servicios debe ser mayor a 0.')),
      );
      return;
    }

    // Validación Soft-Stop de stock físico si ocupa insumo
    if (_insumoProduct != null && newInsumoQty > 0) {
      final insumo = _insumoProduct!;
      final otherReserved = widget.cartController.getReservedQuantityInCart(insumo.id) - widget.item.cantidadInsumoConsumida;
      final totalInsumoRequired = otherReserved + newInsumoQty;

      if (totalInsumoRequired > insumo.stockActual) {
        final decision = await InsufficientStockDialog.show(
          context: context,
          productName: '${insumo.nombre} (Insumo modificado)',
          currentStock: insumo.stockActual,
          requestedQuantity: totalInsumoRequired,
          location: insumo.ubicacion,
        );

        if (!mounted) return;

        if (decision == null) {
          return; // Cancelar
        } else if (decision == InsufficientStockDecision.adjustToLimit) {
          newInsumoQty = max(0.0, insumo.stockActual - otherReserved);
        }
      }
    }

    widget.cartController.updateServiceLine(
      detailItemId: widget.item.id,
      newUnitPrice: newPrice,
      newQuantity: newServiceQty,
      newCantidadInsumoConsumida: newInsumoQty,
      newTierLabel: _currentTier,
    );

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double totalLinea = _currentPrice * _currentServiceQty;
    final insumoNombre = widget.item.insumoUtilizadoNombre ?? widget.item.insumoUtilizadoId ?? 'Insumo físico';
    final insumoStock = _insumoProduct?.stockActual ?? widget.item.stockDisponible;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F7FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.handyman_rounded, color: Color(0xFF006064), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Edición directa de servicio e insumo vinculado',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              // Información del insumo físico
              if (widget.item.hasDynamicInsumo)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFC5E1A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 20, color: Color(0xFF33691E)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Insumo: $insumoNombre',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B5E20)),
                            ),
                            Text(
                              'Existencia actual en almacén: ${insumoStock.toStringAsFixed(0)} pzas | Gaveta: ${_insumoProduct?.ubicacion ?? 'Mostrador'}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF33691E)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // Campo 1: Precio unitario del servicio
              const Text('1. Precio Unitario Cobrado por el Servicio:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      decoration: const InputDecoration(
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: _onPriceChanged,
                      onSubmitted: (_) => _handleConfirm(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: _currentTier == 'Cerrajero'
                          ? const Color(0xFF0D47A1)
                          : _currentTier == 'Taller'
                              ? const Color(0xFF4A148C)
                              : _currentTier == 'Mayoreo'
                                  ? const Color(0xFFE65100)
                                  : (_currentTier == 'Manual' ? const Color(0xFF37474F) : const Color(0xFF2E7D32)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentTier,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),

              // Niveles sugeridos si existen en el producto de servicio
              if (_serviceProduct != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      label: Text('Público: \$${_serviceProduct!.precioVenta.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                      onPressed: () => _selectSuggestedPrice(_serviceProduct!.precioVenta, 'Público'),
                    ),
                    if (_serviceProduct!.precioCerrajero != null && _serviceProduct!.precioCerrajero! > 0)
                      ActionChip(
                        label: Text('Cerrajero: \$${_serviceProduct!.precioCerrajero!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                        onPressed: () => _selectSuggestedPrice(_serviceProduct!.precioCerrajero!, 'Cerrajero'),
                      ),
                    if (_serviceProduct!.precioTaller != null && _serviceProduct!.precioTaller! > 0)
                      ActionChip(
                        label: Text('Taller: \$${_serviceProduct!.precioTaller!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                        onPressed: () => _selectSuggestedPrice(_serviceProduct!.precioTaller!, 'Taller'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),

              // Campo 2: Cantidad de servicios cobrados
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('2. Cantidad de Servicios:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.remove, size: 16),
                              onPressed: () => _adjustServiceQty(-1.0),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _serviceQtyCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                onChanged: _onServiceQtyChanged,
                                onSubmitted: (_) => _handleConfirm(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.add, size: 16),
                              onPressed: () => _adjustServiceQty(1.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Campo 3: Cantidad de insumo físico ocupado
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('3. Insumo Físico Ocupado:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.remove, size: 16),
                              onPressed: () => _adjustInsumoQty(-1.0),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _insumoQtyCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  suffixText: 'pzs',
                                ),
                                onChanged: _onInsumoQtyChanged,
                                onSubmitted: (_) => _handleConfirm(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton.filledTonal(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                              icon: const Icon(Icons.add, size: 16),
                              onPressed: () => _adjustInsumoQty(1.0),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Nota: Pon 0 si el cliente trajo su propia llave/pila, o 2 si se dañó una pieza durante el trabajo.',
                style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),

              // Total de la partida
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total de esta partida:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      '\$${totalLinea.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1F4E79)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Botones de acción
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Guardar Cambios [Enter]'),
                    onPressed: _handleConfirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
