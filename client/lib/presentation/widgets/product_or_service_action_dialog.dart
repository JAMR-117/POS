import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/department_theme.dart';
import '../../data/local/models.dart';
import '../../data/repositories/sales_repository.dart';

class ProductOrServiceResult {
  final bool isService;
  final Product? selectedService;
  final double servicePrice;
  final String priceTierLabel;
  final double insumoQuantityToDeduct;

  const ProductOrServiceResult._({
    required this.isService,
    this.selectedService,
    this.servicePrice = 0.0,
    this.priceTierLabel = 'Público',
    this.insumoQuantityToDeduct = 1.0,
  });

  factory ProductOrServiceResult.directProduct() {
    return const ProductOrServiceResult._(isService: false);
  }

  factory ProductOrServiceResult.service({
    required Product selectedService,
    required double servicePrice,
    required String priceTierLabel,
    required double insumoQuantityToDeduct,
  }) {
    return ProductOrServiceResult._(
      isService: true,
      selectedService: selectedService,
      servicePrice: servicePrice,
      priceTierLabel: priceTierLabel,
      insumoQuantityToDeduct: insumoQuantityToDeduct,
    );
  }

  bool get isDirectProduct => !isService;
}

enum _ActionStep {
  chooseMode,
  selectServiceAndPrice,
  confirmInsumoQuantity,
}

/// Modal ágil 100% compatible con Teclado y Pantalla Táctil para decidir en caja:
/// 1) Venta Directa del Producto Físico [Enter por defecto]
/// 2) Aplicar Servicio del Departamento + Precio Sugerido/Manual + Piezas Físicas a Descontar
class ProductOrServiceActionDialog extends StatefulWidget {
  final Product product;
  final SalesRepository salesRepository;
  final String initialClientTier;
  final double reservedInCart;

  const ProductOrServiceActionDialog({
    super.key,
    required this.product,
    required this.salesRepository,
    this.initialClientTier = 'Público',
    this.reservedInCart = 0.0,
  });

  static Future<ProductOrServiceResult?> show({
    required BuildContext context,
    required Product product,
    required SalesRepository salesRepository,
    String initialClientTier = 'Público',
    double reservedInCart = 0.0,
  }) {
    return showDialog<ProductOrServiceResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ProductOrServiceActionDialog(
        product: product,
        salesRepository: salesRepository,
        initialClientTier: initialClientTier,
        reservedInCart: reservedInCart,
      ),
    );
  }

  @override
  State<ProductOrServiceActionDialog> createState() => _ProductOrServiceActionDialogState();
}

class _ProductOrServiceActionDialogState extends State<ProductOrServiceActionDialog> {
  _ActionStep _step = _ActionStep.chooseMode;

  // Paso 1: 0 = Solo Producto (por defecto), 1 = Aplicar Servicio
  int _selectedMode = 0;
  final FocusNode _step1FocusNode = FocusNode();

  // Paso 2: Servicios aplicables y precio
  List<Product> _applicableServices = [];
  bool _loadingServices = true;
  int _selectedServiceIndex = 0;
  String _selectedTier = 'Público';
  final TextEditingController _priceController = TextEditingController();
  final FocusNode _priceFocusNode = FocusNode();
  bool _updatingPriceProgrammatically = false;

  // Paso 3: Cantidad de piezas físicas a descontar del inventario
  final TextEditingController _insumoQtyController = TextEditingController(text: '1');
  final FocusNode _insumoQtyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedTier = widget.initialClientTier;
    _loadApplicableServices();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _step1FocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _step1FocusNode.dispose();
    _priceController.dispose();
    _priceFocusNode.dispose();
    _insumoQtyController.dispose();
    _insumoQtyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadApplicableServices() async {
    try {
      final list = await widget.salesRepository.getApplicableServicesForDepartment(
        widget.product.departamento,
      );
      // Priorizar servicios específicos del departamento (ej. Duplicado Residencial) sobre los comodín ('Todos')
      list.sort((a, b) {
        final aSpecific = a.departamentosAplicables.trim().toLowerCase() != 'todos' ? 0 : 1;
        final bSpecific = b.departamentosAplicables.trim().toLowerCase() != 'todos' ? 0 : 1;
        if (aSpecific != bSpecific) return aSpecific.compareTo(bSpecific);
        return a.precioVenta.compareTo(b.precioVenta);
      });

      if (!mounted) return;
      setState(() {
        _applicableServices = list;
        _loadingServices = false;
        _selectedServiceIndex = 0;
      });
      if (list.isNotEmpty) {
        _applyServiceSuggestedPrice(list.first, preferredTier: widget.initialClientTier, requestFocus: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingServices = false);
    }
  }

  void _applyServiceSuggestedPrice(
    Product service, {
    required String preferredTier,
    bool requestFocus = true,
  }) {
    String effectiveTier = 'Público';
    double suggested = service.precioVenta;

    if (preferredTier == 'Cerrajero' && service.precioCerrajero != null && service.precioCerrajero! > 0) {
      effectiveTier = 'Cerrajero';
      suggested = service.precioCerrajero!;
    } else if (preferredTier == 'Taller' && service.precioTaller != null && service.precioTaller! > 0) {
      effectiveTier = 'Taller';
      suggested = service.precioTaller!;
    } else if (preferredTier == 'Mayoreo' && service.precioMayoreo != null && service.precioMayoreo! > 0) {
      effectiveTier = 'Mayoreo';
      suggested = service.precioMayoreo!;
    }

    final textVal = suggested.toStringAsFixed(2);
    _updatingPriceProgrammatically = true;
    _selectedTier = effectiveTier;
    _priceController.text = textVal;
    _priceController.selection = TextSelection(baseOffset: 0, extentOffset: textVal.length);
    _updatingPriceProgrammatically = false;

    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _priceFocusNode.requestFocus();
          _priceController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _priceController.text.length,
          );
        }
      });
    }
  }

  void _goToStep2() {
    setState(() {
      _step = _ActionStep.selectServiceAndPrice;
      _selectedMode = 1;
    });
    if (_applicableServices.isNotEmpty) {
      _applyServiceSuggestedPrice(
        _applicableServices[_selectedServiceIndex],
        preferredTier: _selectedTier == 'Manual' ? widget.initialClientTier : _selectedTier,
        requestFocus: true,
      );
    }
  }

  void _goToStep3() {
    if (_applicableServices.isEmpty) return;
    final parsedPrice = double.tryParse(_priceController.text.trim());
    if (parsedPrice == null || parsedPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un precio válido para el servicio.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _step = _ActionStep.confirmInsumoQuantity;
      if (_insumoQtyController.text.trim().isEmpty) {
        _insumoQtyController.text = '1';
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _insumoQtyFocusNode.requestFocus();
        _insumoQtyController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _insumoQtyController.text.length,
        );
      }
    });
  }

  void _confirmDirectProduct() {
    Navigator.of(context).pop(ProductOrServiceResult.directProduct());
  }

  void _confirmServiceAndInsumo() {
    if (_applicableServices.isEmpty) return;
    final service = _applicableServices[_selectedServiceIndex];
    final price = double.tryParse(_priceController.text.trim()) ?? service.precioVenta;
    final qty = double.tryParse(_insumoQtyController.text.trim()) ?? 1.0;
    final safeQty = qty < 0 ? 0.0 : qty;

    Navigator.of(context).pop(
      ProductOrServiceResult.service(
        selectedService: service,
        servicePrice: price < 0 ? 0.0 : price,
        priceTierLabel: _selectedTier,
        insumoQuantityToDeduct: safeQty,
      ),
    );
  }

  void _adjustInsumoQty(double delta) {
    final current = double.tryParse(_insumoQtyController.text.trim()) ?? 1.0;
    final next = (current + delta) < 0 ? 0.0 : (current + delta);
    // Evitar bajar de 1 accidentalmente con [-] salvo que ya estuviera en 0
    final clamped = (delta < 0 && current <= 1.0) ? 1.0 : next;
    final formatted = clamped % 1 == 0 ? clamped.toStringAsFixed(0) : clamped.toStringAsFixed(2);
    setState(() {
      _insumoQtyController.text = formatted;
      _insumoQtyController.selection = TextSelection(baseOffset: 0, extentOffset: formatted.length);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(null);
      return KeyEventResult.handled;
    }

    if (_step == _ActionStep.chooseMode) {
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selectedMode = 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selectedMode = 0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _goToStep2();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyP) {
        setState(() => _selectedMode = 0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        if (_selectedMode == 0) {
          _confirmDirectProduct();
        } else {
          _goToStep2();
        }
        return KeyEventResult.handled;
      }
    } else if (_step == _ActionStep.selectServiceAndPrice) {
      if (key == LogicalKeyboardKey.arrowDown && _applicableServices.isNotEmpty) {
        final nextIdx = (_selectedServiceIndex + 1) % _applicableServices.length;
        setState(() => _selectedServiceIndex = nextIdx);
        _applyServiceSuggestedPrice(
          _applicableServices[nextIdx],
          preferredTier: widget.initialClientTier,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && _applicableServices.isNotEmpty) {
        final prevIdx = (_selectedServiceIndex - 1 + _applicableServices.length) % _applicableServices.length;
        setState(() => _selectedServiceIndex = prevIdx);
        _applyServiceSuggestedPrice(
          _applicableServices[prevIdx],
          preferredTier: widget.initialClientTier,
        );
        return KeyEventResult.handled;
      }
    } else if (_step == _ActionStep.confirmInsumoQuantity) {
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.numpadAdd) {
        _adjustInsumoQty(1.0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.numpadSubtract) {
        _adjustInsumoQty(-1.0);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final prod = widget.product;
    final availableAfterCart = prod.stockActual - widget.reservedInCart;

    return Focus(
      focusNode: _step1FocusNode,
      autofocus: _step == _ActionStep.chooseMode,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProductHeader(prod, availableAfterCart),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: _buildCurrentStepBody(prod, availableAfterCart),
                ),
              ),
              _buildFooterActions(),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDepartmentHeaderIcon(String? rawDept) {
    final d = (rawDept ?? '').trim().toLowerCase();
    if (d.contains('pila') || d.contains('bater')) {
      return Icons.battery_charging_full;
    }
    if (d.contains('control') || d.contains('carcasa') || d.contains('carcaza')) {
      return Icons.settings_remote;
    }
    if (d.contains('cerradura') || d.contains('candado')) {
      return Icons.lock;
    }
    if (d.contains('transponder') || d.contains('chip')) {
      return Icons.memory;
    }
    if (d.contains('moto')) {
      return Icons.two_wheeler;
    }
    if (d.contains('herramienta') || d.contains('accesorio')) {
      return Icons.construction;
    }
    return Icons.vpn_key;
  }

  Widget _buildProductHeader(Product prod, double availableAfterCart) {
    final stockFmt = prod.stockActual % 1 == 0
        ? prod.stockActual.toStringAsFixed(0)
        : prod.stockActual.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1F4E79),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getDepartmentHeaderIcon(prod.departamento), color: Colors.amberAccent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  prod.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                tooltip: 'Cancelar [Esc]',
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DepartmentBadge(departamento: prod.departamento, compact: true),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '📍 Gaveta: ${(prod.ubicacion != null && prod.ubicacion!.isNotEmpty) ? prod.ubicacion : 'Mostrador'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: availableAfterCart <= 0 ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  widget.reservedInCart > 0
                      ? 'Stock: $stockFmt (Disp: ${availableAfterCart.toStringAsFixed(0)})'
                      : 'Stock actual: $stockFmt pzs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: availableAfterCart <= 0 ? Colors.red.shade900 : Colors.green.shade900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'Producto solo: \$${prod.precioVenta.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepBody(Product prod, double availableAfterCart) {
    switch (_step) {
      case _ActionStep.chooseMode:
        return _buildStep1ChooseMode(prod);
      case _ActionStep.selectServiceAndPrice:
        return _buildStep2SelectServiceAndPrice(prod);
      case _ActionStep.confirmInsumoQuantity:
        return _buildStep3ConfirmInsumoQty(prod, availableAfterCart);
    }
  }

  // ---------------------------------------------------------------------------
  // PASO 1: ¿SOLO PRODUCTO O APLICAR SERVICIO?
  // ---------------------------------------------------------------------------
  Widget _buildStep1ChooseMode(Product prod) {
    final bool isDirectSelected = _selectedMode == 0;
    final bool isServiceSelected = _selectedMode == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paso 1 de 3 · ¿Cómo deseas agregar este artículo al ticket?',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 460;
            final card1 = _buildModeCard(
              selected: isDirectSelected,
              icon: Icons.inventory_2_rounded,
              accentColor: const Color(0xFF2E7D32),
              badgeText: 'POR DEFECTO [Enter]',
              title: '📦 Producto solo (Venta directa)',
              subtitle:
                  'Vende únicamente la pieza física a \$${prod.precioVenta.toStringAsFixed(2)} (Público) descontando 1 unidad.',
              onTap: () {
                setState(() => _selectedMode = 0);
                _confirmDirectProduct();
              },
            );

            final card2 = _buildModeCard(
              selected: isServiceSelected,
              icon: Icons.handyman_rounded,
              accentColor: const Color(0xFF00838F),
              badgeText: 'Tecla [S] o Flecha [→]',
              title: '🛠️ Aplicar Servicio',
              subtitle:
                  'Servicio vinculado ocupando este producto como insumo y descontándolo del inventario.',
              onTap: _goToStep2,
            );

            if (isWide) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 12),
                    Expanded(child: card2),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card1,
                const SizedBox(height: 10),
                card2,
              ],
            );
          },
        ),
        if (prod.precioCerrajero != null || prod.precioTaller != null || prod.precioMayoreo != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blueGrey.shade100),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Precios de la pieza:', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700, fontWeight: FontWeight.bold)),
                Text('Público: \$${prod.precioVenta.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                if (prod.precioCerrajero != null && prod.precioCerrajero! > 0)
                  Text('Cerrajero: \$${prod.precioCerrajero!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFF0D47A1), fontWeight: FontWeight.w600)),
                if (prod.precioTaller != null && prod.precioTaller! > 0)
                  Text('Taller: \$${prod.precioTaller!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFF4A148C), fontWeight: FontWeight.w600)),
                if (prod.precioMayoreo != null && prod.precioMayoreo! > 0)
                  Text('Mayoreo: \$${prod.precioMayoreo!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeCard({
    required bool selected,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? accentColor.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accentColor : Colors.grey.shade300,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accentColor.withValues(alpha: 0.15),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected ? accentColor : Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : Colors.blueGrey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: selected ? accentColor : const Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PASO 2: SELECCIÓN DEL SERVICIO Y CONFIRMACIÓN / EDICIÓN DE PRECIO
  // ---------------------------------------------------------------------------
  Widget _buildStep2SelectServiceAndPrice(Product prod) {
    if (_loadingServices) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_applicableServices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(
          'No hay servicios configurados para el departamento "${prod.departamento}". '
          'Puedes dar de alta servicios aplicables en Inventario [F9].',
          style: TextStyle(color: Colors.orange.shade900),
        ),
      );
    }

    final selectedService = _applicableServices[_selectedServiceIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paso 2 de 3 · Selecciona el servicio para "${prod.departamento}" (↑/↓ o toque):',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueGrey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _applicableServices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final srv = _applicableServices[idx];
                final isSelected = idx == _selectedServiceIndex;
                return Material(
                  color: isSelected ? const Color(0xFFE0F7FA) : Colors.white,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedServiceIndex = idx);
                      _applyServiceSuggestedPrice(
                        srv,
                        preferredTier: _selectedTier == 'Manual' ? widget.initialClientTier : _selectedTier,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? const Color(0xFF00838F) : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  srv.nombre,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? const Color(0xFF006064) : Colors.black87,
                                  ),
                                ),
                                if (srv.sku != null && srv.sku!.isNotEmpty)
                                  Text(
                                    'Clave: ${srv.sku} · Aplica a: ${srv.departamentosAplicables}',
                                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '\$${srv.precioVenta.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? const Color(0xFF006064) : const Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFB0BEC5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Precio Sugerido del Servicio (toca un nivel o escribe otro monto):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildTierChip(
                    label: 'Público',
                    price: selectedService.precioVenta,
                    color: const Color(0xFF2E7D32),
                  ),
                  if (selectedService.precioCerrajero != null && selectedService.precioCerrajero! > 0)
                    _buildTierChip(
                      label: 'Cerrajero',
                      price: selectedService.precioCerrajero!,
                      color: const Color(0xFF0D47A1),
                    ),
                  if (selectedService.precioTaller != null && selectedService.precioTaller! > 0)
                    _buildTierChip(
                      label: 'Taller',
                      price: selectedService.precioTaller!,
                      color: const Color(0xFF4A148C),
                    ),
                  if (selectedService.precioMayoreo != null && selectedService.precioMayoreo! > 0)
                    _buildTierChip(
                      label: 'Mayoreo',
                      price: selectedService.precioMayoreo!,
                      color: const Color(0xFFE65100),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      focusNode: _priceFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                      decoration: InputDecoration(
                        labelText: 'Precio a cobrar por el servicio',
                        prefixText: '\$ ',
                        suffixText: 'MXN ($_selectedTier)',
                        filled: true,
                        fillColor: Colors.white,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) {
                        if (!_updatingPriceProgrammatically && _selectedTier != 'Manual') {
                          setState(() => _selectedTier = 'Manual');
                        }
                      },
                      onSubmitted: (_) => _goToStep3(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTierChip({
    required String label,
    required double price,
    required Color color,
  }) {
    final bool selected = _selectedTier == label;
    return ChoiceChip(
      selected: selected,
      selectedColor: color,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? color : Colors.grey.shade400),
      label: Text(
        '$label: \$${price.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: selected ? Colors.white : color,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _applyServiceSuggestedPrice(
            _applicableServices[_selectedServiceIndex],
            preferredTier: label,
          );
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PASO 3: CONFIRMAR PIEZAS FÍSICAS A DESCONTAR DEL INVENTARIO
  // ---------------------------------------------------------------------------
  Widget _buildStep3ConfirmInsumoQty(Product prod, double availableAfterCart) {
    final selectedService = _applicableServices[_selectedServiceIndex];
    final cobro = double.tryParse(_priceController.text.trim()) ?? selectedService.precioVenta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F7FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF80DEEA)),
          ),
          child: Row(
            children: [
              const Icon(Icons.handyman, color: Color(0xFF006064), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${selectedService.nombre}  ·  \$${cobro.toStringAsFixed(2)} ($_selectedTier)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF006064),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '¿Cuántas piezas de "${prod.nombre}" se descontarán del inventario?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF263238),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Presiona [Enter] para descontar 1 pieza (o usa [-] / [+] si se ocuparon más piezas).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: const BorderSide(color: Color(0xFF1F4E79), width: 1.8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _adjustInsumoQty(-1.0),
                child: const Icon(Icons.remove, size: 28, color: Color(0xFF1F4E79)),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _insumoQtyController,
                focusNode: _insumoQtyFocusNode,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                decoration: const InputDecoration(
                  suffixText: 'pzs',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                onSubmitted: (_) => _confirmServiceAndInsumo(),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 56,
              height: 56,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: const BorderSide(color: Color(0xFF1F4E79), width: 1.8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _adjustInsumoQty(1.0),
                child: const Icon(Icons.add, size: 28, color: Color(0xFF1F4E79)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (_step == _ActionStep.selectServiceAndPrice)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _step = _ActionStep.chooseMode;
                  _selectedMode = 0;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _step1FocusNode.requestFocus();
                });
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver'),
            )
          else if (_step == _ActionStep.confirmInsumoQuantity)
            TextButton.icon(
              onPressed: _goToStep2,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Editar Precio'),
            ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar [Esc]'),
          ),
          const SizedBox(width: 10),
          if (_step == _ActionStep.chooseMode)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedMode == 0 ? const Color(0xFF2E7D32) : const Color(0xFF00838F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: Icon(_selectedMode == 0 ? Icons.check_circle_outline : Icons.arrow_forward),
              label: Text(
                _selectedMode == 0 ? 'Confirmar Producto [Enter]' : 'Elegir Servicio [Enter]',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _selectedMode == 0 ? _confirmDirectProduct : _goToStep2,
            )
          else if (_step == _ActionStep.selectServiceAndPrice)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00838F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.check),
              label: const Text(
                'Confirmar Precio [Enter]',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _applicableServices.isEmpty ? null : _goToStep3,
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text(
                'Confirmar y Agregar al Ticket [Enter]',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmServiceAndInsumo,
            ),
        ],
      ),
    );
  }
}
