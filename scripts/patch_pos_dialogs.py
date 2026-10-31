import os

def update_file(path, replacements):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    modified = False
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            modified = True
            print(f"Replaced in {os.path.basename(path)}")
        else:
            print(f"NOT FOUND in {os.path.basename(path)}: {old[:50]}...")
            
    if modified:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)

# 1. pos_screen.dart
pos_replacements = [
    # _refocusSearch safe check
    (
'''  void _refocusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_searchFocusNode.hasFocus && mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }''',
'''  void _refocusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final modalRoute = ModalRoute.of(context);
      if (modalRoute != null && !modalRoute.isCurrent) return;
      if (!_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }'''
    ),

    # _showIncrementalSearchResults
    (
'''  void _showIncrementalSearchResults(List<Product> products) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.key, color: Color(0xFF1F4E79), size: 20),
            const SizedBox(width: 8),
            Text('Coincidencias y Variantes (${products.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 380,
          child: ListView.separated(''',
'''  void _showIncrementalSearchResults(List<Product> products) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Row(
          children: [
            const Icon(Icons.key, color: Color(0xFF1F4E79), size: 20),
            const SizedBox(width: 8),
            Text('Coincidencias y Variantes (${products.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: ListView.separated('''
    ),

    # _tryUpdateQuantity
    (
'''    final newQty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modificar Cantidad: ${item.nombre}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 250,
          child: TextField(''',
'''    final newQty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Text('Modificar Cantidad: ${item.nombre}', style: const TextStyle(fontSize: 16)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 320,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: SingleChildScrollView(
            child: TextField('''
    ),

    # _tryUpdateQuantity close
    (
'''            onSubmitted: (val) {
              final parsed = double.tryParse(val);
              Navigator.pop(ctx, parsed);
            },
          ),
        ),
        actions: [''',
'''            onSubmitted: (val) {
              final parsed = double.tryParse(val);
              Navigator.pop(ctx, parsed);
            },
          ),
          ),
        ),
        actions: ['''
    ),

    # _handleHoldSaleWithAlias
    (
'''    final alias = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('Pausar Ticket [F6]', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(''',
'''    final alias = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: const Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('Pausar Ticket [F6]', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column('''
    ),

    (
'''        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar [Esc]'),''',
'''          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar [Esc]'),'''
    ),

    # _showHeldSalesModal
    (
'''    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Color(0xFFE65100)),
            SizedBox(width: 8),
            Text('Tickets en Espera [F7] (${held.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 320,
          child: ListView.separated(''',
'''    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Color(0xFFE65100)),
            SizedBox(width: 8),
            Text('Tickets en Espera [F7] (${held.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: ListView.separated('''
    ),

    # _showPriceTierMenu (Fix bottom overflowed by 20 pixels)
    (
'''    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Seleccionar Nivel de Precio para:\n\${item.nombre}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),''',
'''    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              maxWidth: 540,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Seleccionar Nivel de Precio para:\n\${item.nombre}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),'''
    ),

    (
'''              ListTile(
                dense: true,
                leading: const Icon(Icons.edit, color: Color(0xFF37474F)),
                title: const Text('Escribir otro precio manualmente...'),
                selected: item.etiquetaPrecio == 'Manual',
                onTap: () => Navigator.pop(ctx, 'Manual'),
              ),
            ],
          ),
        );
      },
    );''',
'''              ListTile(
                dense: true,
                leading: const Icon(Icons.edit, color: Color(0xFF37474F)),
                title: const Text('Escribir otro precio manualmente...'),
                selected: item.etiquetaPrecio == 'Manual',
                onTap: () => Navigator.pop(ctx, 'Manual'),
              ),
            ],
          ),
        ),
        ),
        );
      },
    );'''
    ),

    # manualPrice dialog
    (
'''      final manualPrice = await showDialog<double>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text('Precio Manual: ${item.nombre}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 260,
            child: TextField(''',
'''      final manualPrice = await showDialog<double>(
        context: context,
        builder: (dCtx) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          title: Text('Precio Manual: ${item.nombre}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 320,
              maxHeight: MediaQuery.sizeOf(dCtx).height * 0.75,
            ),
            child: SingleChildScrollView(
              child: TextField('''
    ),

    (
'''              onSubmitted: (v) => Navigator.pop(dCtx, double.tryParse(v)),
            ),
          ),
          actions: [''',
'''              onSubmitted: (v) => Navigator.pop(dCtx, double.tryParse(v)),
            ),
            ),
          ),
          actions: ['''
    ),
]

update_file(r'C:\POS\client\lib\presentation\screens\pos_screen.dart', pos_replacements)
