dialog_path = r'C:\POS\client\lib\presentation\widgets\product_or_service_action_dialog.dart'
with open(dialog_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the button in _buildActions
old_else = """          else
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
            ),"""

new_else = """          else if (_step == _ActionStep.customServiceForm)
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
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _confirmServiceAndInsumo,
            ),"""

content = content.replace(old_else, new_else)

# Fix prefixText
content = content.replace("prefixText: '\\$ '", "prefixText: r'$ '")

# Fix value -> initialValue in DropdownButtonFormField
content = content.replace("value: _availableDepartments.contains(_customServiceDepartment) ? _customServiceDepartment : null,",
                          "initialValue: _availableDepartments.contains(_customServiceDepartment) ? _customServiceDepartment : null,")

with open(dialog_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)

print("Updated product_or_service_action_dialog.dart")
