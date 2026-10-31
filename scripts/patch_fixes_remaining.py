# 1. Patch catalog_import_dialog.dart
with open(r'C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart', 'r', encoding='utf-8') as f:
    cat_code = f.read()

cat_lf = cat_code.replace('\r\n', '\n')

old_cat_block = """      if (kIsWeb) {
        // En Web, cargar de manera nativa y transparente desde assets
        csvString = await rootBundle.loadString(_assetMigratedCsvPath);
      } else {
        // En Desktop, intentar leer primero desde la ruta física local
        final localFile = io.File(_defaultMigratedCsvPath);
        if (localFile.existsSync()) {
          csvString = await localFile.readAsString();
        } else {
          // Respaldo inmediato desde assets si no está en C:\\POS\\migracion\\
          csvString = await rootBundle.loadString(_assetMigratedCsvPath);
        }
      }"""

new_cat_block = """      if (kIsWeb) {
        // En Web, cargar de manera nativa y transparente desde assets
        csvString = await rootBundle.loadString(_assetMigratedCsvPath);
      } else {
        // En Desktop, intentar leer primero desde la ruta física local
        final localData = await readLocalFile(_defaultMigratedCsvPath);
        if (localData != null && localData.isNotEmpty) {
          csvString = localData;
        } else {
          // Respaldo inmediato desde assets si no está en C:\\POS\\migracion\\
          csvString = await rootBundle.loadString(_assetMigratedCsvPath);
        }
      }"""

if old_cat_block in cat_lf:
    cat_lf = cat_lf.replace(old_cat_block, new_cat_block, 1)
    print("Patched catalog_import_dialog.dart")
else:
    print("FAILED to find block in catalog_import_dialog.dart")

if '\r\n' in cat_code:
    cat_lf = cat_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(cat_lf)


# 2. Patch inventory_screen.dart
with open(r'C:\POS\client\lib\presentation\screens\inventory_screen.dart', 'r', encoding='utf-8') as f:
    inv_code = f.read()

inv_lf = inv_code.replace('\r\n', '\n')

old_inv_block = """  // ---------------------------------------------------------------------------
  // PANEL INSPECTOR LATERAL DERECHO (MASTER-DETAIL ERP STYLE)
  // ---------------------------------------------------------------------------
  Widget _buildProductInspectorPanel(Product p) {
    final double marginPct = p.precioVenta > 0
        ? (((p.precioVenta - p.precioCompra) / p.precioVenta) * 100)
        : 0.0;

    return Container(
      width: 360,
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCFD8DC)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(-2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado del Inspector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF263238),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Inspector de Producto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                InkWell(
                  onTap: () => setState(() => _selectedProduct = null),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          // Cuerpo de Detalles
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),"""

new_inv_block = """  // ---------------------------------------------------------------------------
  // MODAL BOTTOM SHEET INSPECTOR PARA TABLETS / PANTALLAS COMPACTAS (< 950px)
  // ---------------------------------------------------------------------------
  void _openInspectorBottomSheet(Product prod) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: _buildProductInspectorPanel(prod, isBottomSheet: true, scrollController: scrollController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PANEL INSPECTOR LATERAL DERECHO (MASTER-DETAIL ERP STYLE / BOTTOM SHEET TABLET)
  // ---------------------------------------------------------------------------
  Widget _buildProductInspectorPanel(Product p, {bool isBottomSheet = false, ScrollController? scrollController}) {
    final double marginPct = p.precioVenta > 0
        ? (((p.precioVenta - p.precioCompra) / p.precioVenta) * 100)
        : 0.0;

    return Container(
      width: isBottomSheet ? double.infinity : 360,
      margin: isBottomSheet ? EdgeInsets.zero : const EdgeInsets.only(top: 8, bottom: 8, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isBottomSheet ? 0 : 6),
        border: isBottomSheet ? null : Border.all(color: const Color(0xFFCFD8DC)),
        boxShadow: isBottomSheet ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(-2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado del Inspector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF263238),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isBottomSheet ? 0 : 5),
                topRight: Radius.circular(isBottomSheet ? 0 : 5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Inspector de Producto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                InkWell(
                  onTap: () {
                    if (isBottomSheet) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _selectedProduct = null);
                    }
                  },
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          // Cuerpo de Detalles
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(14),"""

if old_inv_block in inv_lf:
    inv_lf = inv_lf.replace(old_inv_block, new_inv_block, 1)
    print("Patched inventory_screen.dart")
else:
    print("FAILED to find block in inventory_screen.dart")

if '\r\n' in inv_code:
    inv_lf = inv_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\screens\inventory_screen.dart', 'w', encoding='utf-8') as f:
    f.write(inv_lf)
