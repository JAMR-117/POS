import sys

def patch_file(path, old_sub, new_sub):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    # Normalize CRLF to LF for matching
    content_lf = content.replace('\r\n', '\n')
    old_lf = old_sub.replace('\r\n', '\n')
    new_lf = new_sub.replace('\r\n', '\n')
    if old_lf not in content_lf:
        print(f"FAILED to find match in {path}")
        return False
    replaced = content_lf.replace(old_lf, new_lf, 1)
    # Restore CRLF if original had CRLF
    if '\r\n' in content:
        replaced = replaced.replace('\n', '\r\n')
    with open(path, 'w', encoding='utf-8') as f:
        f.write(replaced)
    print(f"SUCCESSfully patched {path}")
    return True

# 1. cash_movement_dialog.dart
patch_file(
    r"C:\POS\client\lib\presentation\widgets\cash_movement_dialog.dart",
    """              TextField(
                controller: _conceptoController,
                focusNode: _conceptoFocusNode,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Concepto (Ej. Pago de luz, Fondo extra)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                onSubmitted: (_) => _handleSave(),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),""",
    """              TextField(
                controller: _conceptoController,
                focusNode: _conceptoFocusNode,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Concepto (Ej. Pago de luz, Fondo extra)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                onSubmitted: (_) => _handleSave(),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),"""
)

# 2. catalog_import_dialog.dart
patch_file(
    r"C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart",
    """            ]
          ],
        ),
      ),
      actions: [""",
    """            ]
          ],
        ),
      ),
    ),
      actions: ["""
)

# 3. stock_adjustment_dialog.dart
patch_file(
    r"C:\POS\client\lib\presentation\widgets\stock_adjustment_dialog.dart",
    """                validator: (v) => v == null ? 'Seleccione un motivo' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [""",
    """                validator: (v) => v == null ? 'Seleccione un motivo' : null,
              ),
            ],
          ),
        ),
      ),
    ),
      actions: ["""
)

# 4. common_article_dialog.dart
patch_file(
    r"C:\POS\client\lib\presentation\widgets\common_article_dialog.dart",
    """    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fastfood_outlined, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Artículo Común', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _montoController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Monto a cobrar (\$)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (Opcional)',
                hintText: 'Ej. Copias, Servicio, Varios...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        ),
      ),
      actions: [""",
    """    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.fastfood_outlined, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Artículo Común', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _montoController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Monto a cobrar (\$)',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción (Opcional)',
                  hintText: 'Ej. Copias, Servicio, Varios...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: ["""
)

# 5. edit_service_line_dialog.dart
patch_file(
    r"C:\POS\client\lib\presentation\widgets\edit_service_line_dialog.dart",
    """              // Botones de acción
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
              ),
            ],
          ),
        ),
      ),
    );""",
    """                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Botones de acción
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
              ),
            ],
          ),
        ),
      ),
    );"""
)

# 6. clients_screen.dart
patch_file(
    r"C:\POS\client\lib\presentation\screens\clients_screen.dart",
    """          return AlertDialog(
            title: Text('Abonar a cuenta de ${client.nombre}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Deuda Pendiente: \$${client.saldoDeudor.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 16),
                TextField(
                  controller: montoController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  decoration: const InputDecoration(
                    labelText: 'Monto a recibir (\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
              ],
            ),
            ),
            ),
            actions: [""",
    """          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            title: Text('Abonar a cuenta de ${client.nombre}'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Deuda Pendiente: \$${client.saldoDeudor.toStringAsFixed(2)}', 
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: montoController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      decoration: const InputDecoration(
                        labelText: 'Monto a recibir (\$)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: ["""
)

# 7. inventory_screen.dart
patch_file(
    r"C:\POS\client\lib\presentation\screens\inventory_screen.dart",
    """      builder: (ctx) => AlertDialog(
        title: Text('Entrada Rápida: ${p.nombre.isNotEmpty ? p.nombre : p.descripcion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock actual en sistema: ${p.stockActual.toStringAsFixed(0)} piezas'),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cantidad a ingresar (+)', border: OutlineInputBorder()),
            ),
          ],
        ),
        ),
        ),
        actions: [""",
    """      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Text('Entrada Rápida: ${p.nombre.isNotEmpty ? p.nombre : p.descripcion}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stock actual en sistema: ${p.stockActual.toStringAsFixed(0)} piezas'),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad a ingresar (+)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: ["""
)
