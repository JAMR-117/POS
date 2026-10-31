import os

def patch_file(path, replacements):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    modified = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            modified = True
            print(f"[OK] Replaced in {os.path.basename(path)}")
        else:
            print(f"[FAIL] Not found in {os.path.basename(path)}: {old[:60]}...")
            
    if modified:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)

# 1. checkout_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\checkout_dialog.dart', [
    (
'''        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
          contentPadding: const EdgeInsets.all(20.0),''',
'''        child: AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          contentPadding: const EdgeInsets.all(20.0),'''
    ),
    (
'''          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
            child: Column(''',
'''          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
            child: Column('''
    ),
])

# 2. product_or_service_action_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\product_or_service_action_dialog.dart', [
    (
'''      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),''',
'''      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),'''
    ),
])

# 3. quote_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\quote_dialog.dart', [
    (
'''    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 650),''',
'''    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),'''
    ),
])

# 4. cash_movement_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\cash_movement_dialog.dart', [
    (
'''      child: AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),''',
'''      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),'''
    ),
    (
'''        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [''',
'''        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: ['''
    ),
    (
'''                ],
              ),
            ],
          ),
        ),
        actions: [''',
'''                ],
              ),
            ],
          ),
          ),
        ),
        actions: ['''
    ),
])

# 5. shift_cut_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\shift_cut_dialog.dart', [
    (
'''      child: AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),''',
'''      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),'''
    ),
    (
'''        content: SizedBox(
          width: 520,
          child: summary == null''',
'''        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: summary == null'''
    ),
    (
'''    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmación de Cierre Z', style: TextStyle(fontWeight: FontWeight.bold)),''',
'''    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: const Text('Confirmación de Cierre Z', style: TextStyle(fontWeight: FontWeight.bold)),'''
    ),
])

# 6. open_shift_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\open_shift_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Text('Apertura de Caja Requerida', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 380,
        child: Column(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Text('Apertura de Caja Requerida', style: TextStyle(fontWeight: FontWeight.bold)),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column('''
    ),
    (
'''            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Monto Inicial en Efectivo (\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onSubmitted: (_) => _handleOpen(),
            ),
          ],
        ),
      ),
      actions: [''',
'''            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Monto Inicial en Efectivo (\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onSubmitted: (_) => _handleOpen(),
            ),
          ],
        ),
        ),
      ),
      actions: ['''
    ),
])

# 7. catalog_import_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.upload_file, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Importación Masiva (ADM-03)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.upload_file, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Importación Masiva (ADM-03)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column('''
    ),
    (
'''            if (_statusMessage != null)
              Text(_statusMessage!, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
      ),
      actions: [''',
'''            if (_statusMessage != null)
              Text(_statusMessage!, style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
        ),
      ),
      actions: ['''
    ),
])

# 8. stock_adjustment_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\stock_adjustment_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.balance, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Ajuste y Merma Físico', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.balance, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Ajuste y Merma Físico', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Form('''
    ),
    (
'''              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Motivo del Ajuste *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                initialValue: _selectedReason,
                items: _motivos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setState(() => _selectedReason = val),
                validator: (v) => v == null ? 'Seleccione un motivo' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [''',
'''              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Motivo del Ajuste *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                initialValue: _selectedReason,
                items: _motivos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setState(() => _selectedReason = val),
                validator: (v) => v == null ? 'Seleccione un motivo' : null,
              ),
            ],
          ),
        ),
        ),
      ),
      actions: ['''
    ),
])

# 9. quick_product_form_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\quick_product_form_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Alta Rápida de Producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Alta Rápida de Producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column('''
    ),
])

# 10. edit_service_line_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\edit_service_line_dialog.dart', [
    (
'''    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Row(''',
'''    return Dialog(
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
              Row('''
    ),
    (
'''              const SizedBox(height: 16),

              // Información del insumo físico
              if (widget.item.hasDynamicInsumo)''',
'''              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              // Información del insumo físico
              if (widget.item.hasDynamicInsumo)'''
    ),
    (
'''              // Botones de acción
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar [Esc]'),
                  ),''',
'''                    ],
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
                    child: const Text('Cancelar [Esc]'),
                  ),'''
    ),
])

# 11. client_selection_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\client_selection_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.people_outline, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Asignar Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 450,
        child: Column(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.people_outline, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Asignar Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column('''
    ),
])

# 12. common_article_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\common_article_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.local_offer_outlined, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Artículo Común [F2]'),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.local_offer_outlined, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Artículo Común [F2]'),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column('''
    ),
    (
'''            TextField(
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
      actions: [''',
'''            TextField(
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
      actions: ['''
    ),
])

# 13. insufficient_stock_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\insufficient_stock_dialog.dart', [
    (
'''      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),''',
'''      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),'''
    ),
    (
'''        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [''',
'''        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ['''
    ),
    (
'''            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),''',
'''            ],
          ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),'''
    ),
])

# 14. admin_auth_dialog.dart
patch_file(r'C:\POS\client\lib\presentation\widgets\admin_auth_dialog.dart', [
    (
'''    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.security, color: Color(0xFFD32F2F)),
          SizedBox(width: 8),
          Text('Autorización Requerida'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [''',
'''    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: const Row(
        children: [
          Icon(Icons.security, color: Color(0xFFD32F2F)),
          SizedBox(width: 8),
          Text('Autorización Requerida'),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['''
    ),
    (
'''            onSubmitted: (_) => _validatePin(),
          ),
        ],
      ),
      actions: [''',
'''            onSubmitted: (_) => _validatePin(),
          ),
        ],
      ),
      ),
      ),
      actions: ['''
    ),
])

# 15. clients_screen.dart (form & abono dialogs)
patch_file(r'C:\POS\client\lib\presentation\screens\clients_screen.dart', [
    (
'''          return AlertDialog(
            title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente / Cerrajero'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(''',
'''          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente / Cerrajero'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column('''
    ),
    (
'''          return AlertDialog(
            title: Text('Abonar a cuenta de \${client.nombre}'),
            content: Column(''',
'''          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            title: Text('Abonar a cuenta de \${client.nombre}'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 400,
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column('''
    ),
    (
'''                TextField(
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
            actions: [''',
'''                TextField(
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
            actions: ['''
    ),
])

# 16. sales_history_screen.dart (details modal)
patch_file(r'C:\POS\client\lib\presentation\screens\sales_history_screen.dart', [
    (
'''    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ticket: \${sale.folioTicket}'),
            if (sale.estatus == 'cancelado')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                child: const Text('CANCELADO', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: Column(''',
'''    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ticket: \${sale.folioTicket}'),
            if (sale.estatus == 'cancelado')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                child: const Text('CANCELADO', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: Column('''
    ),
])

# 17. inventory_screen.dart (quick entry & delete confirm)
patch_file(r'C:\POS\client\lib\presentation\screens\inventory_screen.dart', [
    (
'''    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entrada Rápida: \${p.nombre.isNotEmpty ? p.nombre : p.descripcion}'),
        content: Column(''',
'''    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Text('Entrada Rápida: \${p.nombre.isNotEmpty ? p.nombre : p.descripcion}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column('''
    ),
    (
'''            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cantidad a ingresar (+)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [''',
'''            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cantidad a ingresar (+)', border: OutlineInputBorder()),
            ),
          ],
        ),
        ),
        ),
        actions: ['''
    ),
    (
'''    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Producto?'),''',
'''    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: const Text('¿Eliminar Producto?'),'''
    ),
])
