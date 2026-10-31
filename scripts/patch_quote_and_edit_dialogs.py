# 1. Patch quote_dialog.dart
with open(r'C:\POS\client\lib\presentation\widgets\quote_dialog.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text_lf = text.replace('\r\n', '\n')

old_actions_block = """            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar Texto (WhatsApp / Mail)'),
                    onPressed: () {
                      final plainText = _generatePlainTextTicket(folio, fechaStr);
                      Clipboard.setData(ClipboardData(text: plainText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cotización copiada al portapapeles.'),
                          backgroundColor: Color(0xFF2E7D32),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),"""

new_actions_block = """            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar Texto'),
                    onPressed: () {
                      final plainText = _generatePlainTextTicket(folio, fechaStr);
                      Clipboard.setData(ClipboardData(text: plainText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cotización copiada al portapapeles.'),
                          backgroundColor: Color(0xFF2E7D32),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),"""

if old_actions_block in text_lf:
    text_lf = text_lf.replace(old_actions_block, new_actions_block, 1)
    print("Patched quote_dialog actions")
else:
    print("Failed to find quote_dialog actions")

if '\r\n' in text:
    text_lf = text_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\widgets\quote_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(text_lf)


# 2. Patch edit_service_line_dialog.dart
with open(r'C:\POS\client\lib\presentation\widgets\edit_service_line_dialog.dart', 'r', encoding='utf-8') as f:
    edit_text = f.read()

edit_lf = edit_text.replace('\r\n', '\n')

# Tighten the IconButton.filledTonal constraints
edit_lf = edit_lf.replace(
    'IconButton.filledTonal(\n                              visualDensity: VisualDensity.compact,',
    'IconButton.filledTonal(\n                              visualDensity: VisualDensity.compact,\n                              constraints: const BoxConstraints.tightFor(width: 32, height: 32),'
)

# Wrap action buttons
old_edit_actions = """              // Botones de acción
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
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
              ),"""

new_edit_actions = """              // Botones de acción
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
              ),"""

if old_edit_actions in edit_lf:
    edit_lf = edit_lf.replace(old_edit_actions, new_edit_actions, 1)
    print("Patched edit_service_line actions")
else:
    print("Failed to find edit_service_line actions")

if '\r\n' in edit_text:
    edit_lf = edit_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\widgets\edit_service_line_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(edit_lf)
