import re

dialog_path = r'C:\POS\client\lib\presentation\widgets\product_or_service_action_dialog.dart'
with open(dialog_path, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update _ActionStep enum
code = code.replace(
"""enum _ActionStep {
  chooseMode,
  selectServiceAndPrice,
  confirmInsumoQuantity,
}""",
"""enum _ActionStep {
  chooseMode,
  selectServiceAndPrice,
  confirmInsumoQuantity,
  customServiceForm,
}"""
)

# 2. Add controllers and state to _ProductOrServiceActionDialogState
old_controllers_anchor = "  // Paso 3: Cantidad de piezas físicas a descontar del inventario\n  final TextEditingController _insumoQtyController = TextEditingController(text: '1');\n  final FocusNode _insumoQtyFocusNode = FocusNode();"
new_controllers = """  // Paso 3: Cantidad de piezas físicas a descontar del inventario
  final TextEditingController _insumoQtyController = TextEditingController(text: '1');
  final FocusNode _insumoQtyFocusNode = FocusNode();

  // Paso Especial: Servicio Personalizado al Momento
  final TextEditingController _customServiceNameController = TextEditingController();
  final TextEditingController _customServicePriceController = TextEditingController();
  final TextEditingController _customServiceCerrajeroPriceController = TextEditingController();
  final TextEditingController _customServiceTallerPriceController = TextEditingController();
  final TextEditingController _customServiceMayoreoPriceController = TextEditingController();
  final TextEditingController _customServiceInsumoQtyController = TextEditingController(text: '1');
  final FocusNode _customServiceNameFocusNode = FocusNode();
  final FocusNode _customServicePriceFocusNode = FocusNode();
  bool _customServiceIsPersistent = false;
  String _customServiceDepartment = 'Servicios de Cerrajería';
  List<String> _availableDepartments = [];
  bool _savingCustomService = false;"""

code = code.replace(old_controllers_anchor, new_controllers)

# 3. Add department loader in initState
old_init = """    _selectedTier = widget.initialClientTier;
    _loadApplicableServices();"""
new_init = """    _selectedTier = widget.initialClientTier;
    _loadApplicableServices();
    _loadDepartments();"""
code = code.replace(old_init, new_init)

# 4. Dispose custom controllers
old_dispose = """    _insumoQtyController.dispose();
    _insumoQtyFocusNode.dispose();
    super.dispose();"""
new_dispose = """    _insumoQtyController.dispose();
    _insumoQtyFocusNode.dispose();
    _customServiceNameController.dispose();
    _customServicePriceController.dispose();
    _customServiceCerrajeroPriceController.dispose();
    _customServiceTallerPriceController.dispose();
    _customServiceMayoreoPriceController.dispose();
    _customServiceInsumoQtyController.dispose();
    _customServiceNameFocusNode.dispose();
    _customServicePriceFocusNode.dispose();
    super.dispose();"""
code = code.replace(old_dispose, new_dispose)

# 5. Add custom service methods before _applyServiceSuggestedPrice
methods_anchor = "  void _applyServiceSuggestedPrice("
new_methods = """  Future<void> _loadDepartments() async {
    try {
      final deptos = await widget.salesRepository.getDepartmentNames();
      if (!mounted) return;
      setState(() {
        _availableDepartments = deptos;
        if (deptos.contains(widget.product.departamento)) {
          _customServiceDepartment = widget.product.departamento;
        } else if (deptos.contains('Servicios de Cerrajería')) {
          _customServiceDepartment = 'Servicios de Cerrajería';
        } else if (deptos.isNotEmpty) {
          _customServiceDepartment = deptos.first;
        }
      });
    } catch (_) {}
  }

  void _goToCustomServiceForm() {
    _customServiceNameController.text = 'Servicio con ${widget.product.nombre}';
    _customServicePriceController.text = _priceController.text.isNotEmpty ? _priceController.text : '50.00';
    _customServiceCerrajeroPriceController.clear();
    _customServiceTallerPriceController.clear();
    _customServiceMayoreoPriceController.clear();
    _customServiceInsumoQtyController.text = '1';
    _customServiceIsPersistent = false;
    setState(() {
      _step = _ActionStep.customServiceForm;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _customServiceNameFocusNode.requestFocus();
        _customServiceNameController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _customServiceNameController.text.length,
        );
      }
    });
  }

  Future<void> _confirmCustomService() async {
    final name = _customServiceNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el nombre del servicio.'), backgroundColor: Colors.red),
      );
      return;
    }
    final publicPrice = double.tryParse(_customServicePriceController.text.trim());
    if (publicPrice == null || publicPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un precio válido para el servicio.'), backgroundColor: Colors.red),
      );
      return;
    }

    final cerrajeroPrice = double.tryParse(_customServiceCerrajeroPriceController.text.trim());
    final tallerPrice = double.tryParse(_customServiceTallerPriceController.text.trim());
    final mayoreoPrice = double.tryParse(_customServiceMayoreoPriceController.text.trim());
    final insumoQty = double.tryParse(_customServiceInsumoQtyController.text.trim()) ?? 1.0;
    final safeInsumoQty = insumoQty < 0 ? 0.0 : insumoQty;

    setState(() => _savingCustomService = true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rand = (1000 + (timestamp % 9000)).toString();
    final serviceId = _customServiceIsPersistent ? 'SRV-$timestamp-$rand' : 'SRV-TEMP-$timestamp';
    final depto = _customServiceIsPersistent ? _customServiceDepartment : widget.product.departamento;

    final customService = Product(
      id: serviceId,
      sku: 'SRV-$rand',
      codigoBarras: null,
      nombre: name,
      descripcion: name,
      marca: 'Servicio Propio',
      precioCompra: 0.0,
      precioVenta: publicPrice,
      precioCerrajero: (cerrajeroPrice != null && cerrajeroPrice > 0) ? cerrajeroPrice : null,
      precioTaller: (tallerPrice != null && tallerPrice > 0) ? tallerPrice : null,
      precioMayoreo: (mayoreoPrice != null && mayoreoPrice > 0) ? mayoreoPrice : null,
      departamento: depto,
      departamentosAplicables: widget.product.departamento,
      stockActual: 9999.0,
      esServicio: true,
      insumoVinculadoId: safeInsumoQty > 0 ? widget.product.id : null,
      cantidadInsumo: safeInsumoQty,
    );

    if (_customServiceIsPersistent) {
      try {
        await widget.salesRepository.saveCustomService(customService);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aviso: Se agregó al ticket pero falló guardar en catálogo: $e'), backgroundColor: Colors.orange),
          );
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pop(
        ProductOrServiceResult.service(
          selectedService: customService,
          servicePrice: publicPrice,
          priceTierLabel: 'Público',
          insumoQuantityToDeduct: safeInsumoQty,
        ),
      );
    }
  }

  void _applyServiceSuggestedPrice("""
code = code.replace(methods_anchor, new_methods)

# 6. Update keyboard shortcuts in _handleKeyEvent
old_key_handler = """      if (key == LogicalKeyboardKey.arrowUp && _applicableServices.isNotEmpty) {
        final prevIdx = (_selectedServiceIndex - 1 + _applicableServices.length) % _applicableServices.length;
        setState(() => _selectedServiceIndex = prevIdx);
        _applyServiceSuggestedPrice(
          _applicableServices[prevIdx],
          preferredTier: widget.initialClientTier,
        );
        return KeyEventResult.handled;
      }
    } else if (_step == _ActionStep.confirmInsumoQuantity) {"""

new_key_handler = """      if (key == LogicalKeyboardKey.arrowUp && _applicableServices.isNotEmpty) {
        final prevIdx = (_selectedServiceIndex - 1 + _applicableServices.length) % _applicableServices.length;
        setState(() => _selectedServiceIndex = prevIdx);
        _applyServiceSuggestedPrice(
          _applicableServices[prevIdx],
          preferredTier: widget.initialClientTier,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        _goToCustomServiceForm();
        return KeyEventResult.handled;
      }
    } else if (_step == _ActionStep.customServiceForm) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        _confirmCustomService();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _step = _ActionStep.selectServiceAndPrice);
        return KeyEventResult.handled;
      }
    } else if (_step == _ActionStep.confirmInsumoQuantity) {"""

code = code.replace(old_key_handler, new_key_handler)

# 7. Update _buildCurrentStepBody
old_step_body = """      case _ActionStep.confirmInsumoQuantity:
        return _buildStep3ConfirmInsumoQty(prod, availableAfterCart);
    }"""
new_step_body = """      case _ActionStep.confirmInsumoQuantity:
        return _buildStep3ConfirmInsumoQty(prod, availableAfterCart);
      case _ActionStep.customServiceForm:
        return _buildCustomServiceForm(prod);
    }"""
code = code.replace(old_step_body, new_step_body)

# 8. Update _buildStep2SelectServiceAndPrice empty state to include the button
old_empty_step2 = """    if (_applicableServices.isEmpty) {
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
    }"""

new_empty_step2 = """    if (_applicableServices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No hay servicios precargados para "${prod.departamento}". '
                    'Crea uno al instante con el botón de abajo:',
                    style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00838F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add_circle, size: 20),
            label: const Text('➕ Crear Servicio Personalizado al Momento [N]', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: _goToCustomServiceForm,
          ),
        ],
      );
    }"""
code = code.replace(old_empty_step2, new_empty_step2)

# 9. Add custom service button in normal Step 2 list header
old_step2_header = """        Text(
          'Paso 2 de 3 · Selecciona el servicio para "${prod.departamento}" (↑/↓ o toque):',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
        ),
        const SizedBox(height: 8),"""

new_step2_header = """        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Paso 2 de 3 · Selecciona el servicio para "${prod.departamento}":',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00838F),
                side: const BorderSide(color: Color(0xFF00838F)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('➕ Personalizado [N]', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _goToCustomServiceForm,
            ),
          ],
        ),
        const SizedBox(height: 8),"""
code = code.replace(old_step2_header, new_step2_header)

# 10. Append _buildCustomServiceForm before _buildActions
actions_anchor = "  Widget _buildActions(Product prod, double availableAfterCart) {"
new_form_widget = """  // ---------------------------------------------------------------------------
  // PASO ESPECIAL: FORMULARIO DE SERVICIO PERSONALIZADO AL MOMENTO
  // ---------------------------------------------------------------------------
  Widget _buildCustomServiceForm(Product prod) {
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
              const Icon(Icons.auto_fix_high, color: Color(0xFF00838F), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Servicio Exprés con insumo: ${prod.nombre} (${prod.departamento})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF006064), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Nombre del Servicio
        TextField(
          controller: _customServiceNameController,
          focusNode: _customServiceNameFocusNode,
          decoration: const InputDecoration(
            labelText: 'Nombre del Servicio *',
            hintText: 'ej. Instalación de batería especial, Corte regata forja...',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.handyman_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        // Fila: Precio Público y Consumo de Insumo
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _customServicePriceController,
                focusNode: _customServicePriceFocusNode,
                keyboardType: const TextInputTextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio Público ($) *',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueGrey.shade200),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Descontar pieza:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 22, color: Color(0xFF1F4E79)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final cur = double.tryParse(_customServiceInsumoQtyController.text) ?? 1.0;
                            final nxt = (cur - 1.0) < 0 ? 0.0 : (cur - 1.0);
                            setState(() => _customServiceInsumoQtyController.text = nxt.toStringAsFixed(0));
                          },
                        ),
                        SizedBox(
                          width: 35,
                          child: Text(
                            _customServiceInsumoQtyController.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 22, color: Color(0xFF1F4E79)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final cur = double.tryParse(_customServiceInsumoQtyController.text) ?? 1.0;
                            setState(() => _customServiceInsumoQtyController.text = (cur + 1.0).toStringAsFixed(0));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Precios opcionales por nivel
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customServiceCerrajeroPriceController,
                keyboardType: const TextInputTextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cerrajero ($)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _customServiceTallerPriceController,
                keyboardType: const TextInputTextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Taller ($)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _customServiceMayoreoPriceController,
                keyboardType: const TextInputTextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Mayoreo ($)',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Segmented Control de Persistencia
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCFD8DC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Persistencia del Servicio:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.flash_on, size: 16),
                    label: Text('⚡ Solo esta venta', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.save_outlined, size: 16),
                    label: Text('💾 Guardar servicio', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_customServiceIsPersistent},
                onSelectionChanged: (setVal) {
                  setState(() => _customServiceIsPersistent = setVal.first);
                },
              ),
              if (_customServiceIsPersistent) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _availableDepartments.contains(_customServiceDepartment) ? _customServiceDepartment : null,
                  decoration: const InputDecoration(
                    labelText: 'Departamento a asignar',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _availableDepartments.map((d) {
                    return DropdownMenuItem<String>(value: d, child: Text(d, style: const TextStyle(fontSize: 13)));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _customServiceDepartment = val);
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions(Product prod, double availableAfterCart) {"""
code = code.replace(actions_anchor, new_form_widget)

# 11. Update _buildActions for customServiceForm
old_back_button = """        if (_step == _ActionStep.confirmInsumoQuantity)
          TextButton.icon(
            onPressed: _goToStep2,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Editar Precio'),
          ),"""

new_back_button = """        if (_step == _ActionStep.confirmInsumoQuantity)
          TextButton.icon(
            onPressed: _goToStep2,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Editar Precio'),
          )
        else if (_step == _ActionStep.customServiceForm)
          TextButton.icon(
            onPressed: () => setState(() => _step = _ActionStep.selectServiceAndPrice),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Volver a Servicios'),
          ),"""
code = code.replace(old_back_button, new_back_button)

old_confirm_button = """          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text(
                'Confirmar y Agregar al Ticket [Enter]',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmServiceAndInsumo,
            ),"""

new_confirm_button = """          else if (_step == _ActionStep.customServiceForm)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: _savingCustomService
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle),
              label: const Text(
                'Agregar Servicio al Ticket [Enter]',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _savingCustomService ? null : _confirmCustomService,
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
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmServiceAndInsumo,
            ),"""
code = code.replace(old_confirm_button, new_confirm_button)

# Also fix TextInputType typo in form widget if any: TextInputTextInputType -> TextInputType
code = code.replace("TextInputTextInputType", "TextInputType")

with open(dialog_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(code)

print("Updated product_or_service_action_dialog.dart for Phase 2")
