with open(r'C:\POS\client\lib\presentation\screens\inventory_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

code_lf = code.replace('\r\n', '\n')

# 1. Condition for showing side inspector in desktop
old_row = """              // Inspector Lateral Derecho (360px)
              if (_selectedProduct != null)
                _buildProductInspectorPanel(_selectedProduct!),"""

new_row = """              // Inspector Lateral Derecho (360px) solo en pantallas amplias (>= 950px)
              if (_selectedProduct != null && MediaQuery.sizeOf(context).width >= 950)
                _buildProductInspectorPanel(_selectedProduct!),"""

code_lf = code_lf.replace(old_row, new_row)

# 2. Row onTap behavior
old_ontap = """                  onTap: () {
                    setState(() {
                      if (_selectedProduct?.id == prod.id) {
                        _selectedProduct = null;
                      } else {
                        _selectedProduct = prod;
                      }
                    });
                  },"""

new_ontap = """                  onTap: () {
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    if (screenWidth < 950) {
                      _openInspectorBottomSheet(prod);
                    } else {
                      setState(() {
                        if (_selectedProduct?.id == prod.id) {
                          _selectedProduct = null;
                        } else {
                          _selectedProduct = prod;
                        }
                      });
                    }
                  },"""

code_lf = code_lf.replace(old_ontap, new_ontap)

# 3. Add _openInspectorBottomSheet and modify _buildProductInspectorPanel
old_inspector_method = """  // ---------------------------------------------------------------------------
  // INSPECTOR LATERAL MASTER-DETAIL (360px)
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

new_inspector_method = """  // ---------------------------------------------------------------------------
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
  // INSPECTOR LATERAL MASTER-DETAIL (360px EN ESCRITORIO O BOTTOM SHEET EN TABLET)
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

code_lf = code_lf.replace(old_inspector_method, new_inspector_method)

if '\r\n' in code:
    code_lf = code_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\screens\inventory_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code_lf)

print("Updated inventory_screen.dart successfully")
