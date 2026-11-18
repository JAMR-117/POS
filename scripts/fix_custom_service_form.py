# 1. Fix pos_screen.dart unused import
pos_path = r'C:\POS\client\lib\presentation\screens\pos_screen.dart'
with open(pos_path, 'r', encoding='utf-8') as f:
    pos_content = f.read()

pos_content = pos_content.replace("import '../../core/department_theme.dart';\n", "")
pos_content = pos_content.replace("import '../../core/department_theme.dart';\r\n", "")

with open(pos_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(pos_content)
print("Cleaned unused import in pos_screen.dart")

# 2. Fix product_or_service_action_dialog.dart
dialog_path = r'C:\POS\client\lib\presentation\widgets\product_or_service_action_dialog.dart'
with open(dialog_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

custom_form_code = '''
  // ---------------------------------------------------------------------------
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
'''

content = ''.join(lines)

# Update back button
old_back = """          else if (_step == _ActionStep.confirmInsumoQuantity)
            TextButton.icon(
              onPressed: _goToStep2,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Editar Precio'),
            )"""

new_back = """          else if (_step == _ActionStep.confirmInsumoQuantity)
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
            )"""
content = content.replace(old_back, new_back)

# Update confirm button
old_confirm = """          else if (_step == _ActionStep.selectServiceAndPrice)
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
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmServiceAndInsumo,
            ),"""

new_confirm = """          else if (_step == _ActionStep.selectServiceAndPrice)
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
          else if (_step == _ActionStep.customServiceForm)
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
content = content.replace(old_confirm, new_confirm)

# Insert custom_form_code right before the last closing brace
last_brace_idx = content.rfind('}')
content = content[:last_brace_idx] + custom_form_code + '\n}\n'

with open(dialog_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print("Successfully patched product_or_service_action_dialog.dart")
