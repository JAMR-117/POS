with open(r'C:\POS\client\lib\presentation\screens\pos_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Fix _showHeldSalesModal
old_held = """    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Text('Tickets en Espera [F7] (${held.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 320,
          child: ListView.separated("""

new_held = """    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        title: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Text('Tickets en Espera [F7] (${held.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: ListView.separated("""

if old_held in c:
    c = c.replace(old_held, new_held)
    print("HELD REPLACED")
else:
    print("HELD NOT FOUND")

# Fix _showPriceTierMenu
old_tier = """    final selected = await showModalBottomSheet<String>(
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
                'Seleccionar Nivel de Precio para:\\n${item.nombre}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),"""

new_tier = """    final selected = await showModalBottomSheet<String>(
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
                      'Seleccionar Nivel de Precio para:\\n${item.nombre}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),"""

if old_tier in c:
    c = c.replace(old_tier, new_tier)
    print("TIER REPLACED")
else:
    print("TIER NOT FOUND")

# Clean closing in tier menu
old_close = """              ListTile(
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
    );"""

new_close = """              ListTile(
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
        ),
        );
      },
    );"""

if old_close in c:
    c = c.replace(old_close, new_close)
    print("CLOSE REPLACED")

with open(r'C:\POS\client\lib\presentation\screens\pos_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)
