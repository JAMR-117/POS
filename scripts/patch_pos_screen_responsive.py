import re

with open(r'C:\POS\client\lib\presentation\screens\pos_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update LayoutBuilder in build()
old_build_body = """            body: SafeArea(
              child: Column(
                children: [
                  _buildHeaderBar(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 7, child: _buildActiveTicketTable()),
                        Expanded(flex: 3, child: _buildRightLiquidationPanel()),
                      ],
                    ),
                  ),
                  _buildKeyboardShortcutsFooter(),
                ],
              ),
            ),"""

new_build_body = """            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  return Column(
                    children: [
                      _buildHeaderBar(),
                      Expanded(
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 7, child: _buildActiveTicketTable()),
                                  SizedBox(
                                    width: (constraints.maxWidth * 0.28).clamp(300.0, 360.0),
                                    child: SingleChildScrollView(
                                      child: _buildRightLiquidationPanel(),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: _buildActiveTicketTable()),
                                  _buildCompactLiquidationBar(),
                                ],
                              ),
                      ),
                      _buildKeyboardShortcutsFooter(),
                    ],
                  );
                },
              ),
            ),"""

# 2. Add _buildCompactLiquidationBar and fix Spacer in _buildRightLiquidationPanel
old_liquidation = """              // Botón de Cotización / Ticket Digital [F8]
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F4E79),
                  side: const BorderSide(color: Color(0xFF1F4E79), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.request_quote_outlined),
                label: const Text(
                  'COTIZAR / TICKET DIGITAL [F8]',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: widget.cartController.isEmpty ? null : _openQuoteDialog,
              ),
              const SizedBox(height: 12),"""

new_liquidation_bar = """  // ---------------------------------------------------------------------------
  // BARRA COMPACTA INFERIOR PARA TABLET VERTICAL / COMPACTA (< 900px)
  // ---------------------------------------------------------------------------
  Widget _buildCompactLiquidationBar() {
    return AnimatedBuilder(
      animation: widget.cartController,
      builder: (context, _) {
        final total = widget.cartController.total;
        final subtotal = widget.cartController.subtotal;
        final descuento = widget.cartController.descuentoTotal;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, -3),
              ),
            ],
            border: const Border(top: BorderSide(color: Color(0xFFCFD8DC))),
          ),
          child: Row(
            children: [
              // Total y desglose
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Subtotal: \$${subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        if (descuento > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '-Desc: \$${descuento.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'TOTAL: \$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F4E79),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Botón Cotizar
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F4E79),
                  side: const BorderSide(color: Color(0xFF1F4E79)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  minimumSize: const Size(44, 44),
                ),
                icon: const Icon(Icons.request_quote_outlined, size: 18),
                label: const Text('COTIZAR [F8]', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: widget.cartController.isEmpty ? null : _openQuoteDialog,
              ),
              const SizedBox(width: 8),
              // Botón Cobrar
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  minimumSize: const Size(110, 44),
                ),
                icon: const Icon(Icons.point_of_sale, size: 20),
                label: const Text(
                  'COBRAR [F12]',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: widget.cartController.isEmpty ? null : _triggerCheckout,
              ),
            ],
          ),
        );
      },
    );
  }

"""

# Normalize CRLF
code_lf = code.replace('\r\n', '\n')
old_build_body_lf = old_build_body.replace('\r\n', '\n')
new_build_body_lf = new_build_body.replace('\r\n', '\n')

if old_build_body_lf in code_lf:
    code_lf = code_lf.replace(old_build_body_lf, new_build_body_lf, 1)
    print("Replaced build body")
else:
    print("FAILED to replace build body")

# Replace Spacer in _buildRightLiquidationPanel
code_lf = code_lf.replace(
    '              const Spacer(),\n\n              // Botón de Cotización / Ticket Digital [F8]',
    '              const SizedBox(height: 20),\n\n              // Botón de Cotización / Ticket Digital [F8]'
)

# Insert _buildCompactLiquidationBar before _buildRightLiquidationPanel
code_lf = code_lf.replace(
    '  // ---------------------------------------------------------------------------\n  // PANEL DE LIQUIDACIÓN Y BOTÓN DE COTIZACIÓN [F8]\n  // ---------------------------------------------------------------------------\n  Widget _buildRightLiquidationPanel() {',
    new_liquidation_bar.replace('\r\n', '\n') + '  // ---------------------------------------------------------------------------\n  // PANEL DE LIQUIDACIÓN Y BOTÓN DE COTIZACIÓN [F8]\n  // ---------------------------------------------------------------------------\n  Widget _buildRightLiquidationPanel() {'
)

# 3. Touch target sizes in quantity column
old_qty_col = """                          // Cantidad interactiva con botones [-] y [+]
                          SizedBox(
                            width: 110,
                            child: Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => widget.cartController.decrementItem(item.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.remove, size: 16, color: Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () => _showQuantityDialog(item),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.cantidad.toStringAsFixed(isGranel ? 3 : 0),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => _tryIncrementQuantity(item),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.add, size: 16, color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),"""

new_qty_col = """                          // Cantidad interactiva con botones [-] y [+] (Touch targets ergonómicos >= 40px)
                          SizedBox(
                            width: 125,
                            child: Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => widget.cartController.decrementItem(item.id),
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Center(child: Icon(Icons.remove, size: 18, color: Colors.black87)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () => _showQuantityDialog(item),
                                    child: Container(
                                      constraints: const BoxConstraints(minHeight: 40),
                                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade300),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Center(
                                        child: Text(
                                          item.cantidad.toStringAsFixed(isGranel ? 3 : 0),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => _tryIncrementQuantity(item),
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Center(child: Icon(Icons.add, size: 18, color: Colors.black87)),
                                  ),
                                ),
                              ],
                            ),
                          ),"""

code_lf = code_lf.replace(old_qty_col.replace('\r\n', '\n'), new_qty_col.replace('\r\n', '\n'))

# 4. Touch target in delete button
old_del_btn = """                          // Botón Eliminar Fila
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Color(0xFFE53935)),
                              onPressed: () {
                                widget.cartController.removeItem(item.id);
                                _refocusSearch();
                              },
                            ),
                          ),"""

new_del_btn = """                          // Botón Eliminar Fila (Touch target >= 44x44)
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 20, color: Color(0xFFE53935)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                              tooltip: 'Quitar del ticket',
                              onPressed: () {
                                widget.cartController.removeItem(item.id);
                                _refocusSearch();
                              },
                            ),
                          ),"""

code_lf = code_lf.replace(old_del_btn.replace('\r\n', '\n'), new_del_btn.replace('\r\n', '\n'))

# 5. Header bar wrap icons in SingleChildScrollView
old_header_icons = """          // Buscar [F1]
          IconButton(
            icon: const Icon(Icons.manage_search, color: Color(0xFF1F4E79)),
            tooltip: 'Buscar [F1]',
            onPressed: _openAdvancedProductSearch,
          ),"""

new_header_icons = """          // Iconos de acción con scroll horizontal para pantallas táctiles estrechas
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.manage_search, color: Color(0xFF1F4E79)),
                    tooltip: 'Buscar [F1]',
                    onPressed: _openAdvancedProductSearch,
                  ),"""

code_lf = code_lf.replace(old_header_icons.replace('\r\n', '\n'), new_header_icons.replace('\r\n', '\n'))

old_header_end = """              tooltip: 'Bloquear Terminal / Cerrar Sesión',
              onPressed: _handleLogout,
            ),
          ),
        ],
      ),
    );"""

new_header_end = """              tooltip: 'Bloquear Terminal / Cerrar Sesión',
              onPressed: _handleLogout,
            ),
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );"""

code_lf = code_lf.replace(old_header_end.replace('\r\n', '\n'), new_header_end.replace('\r\n', '\n'))

# 6. Touch target for _buildKeyBadge in footer
code_lf = code_lf.replace(
    '        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),',
    '        constraints: const BoxConstraints(minHeight: 38),\n        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),'
)

# Restore CRLF
if '\r\n' in code:
    code_lf = code_lf.replace('\n', '\r\n')

with open(r'C:\POS\client\lib\presentation\screens\pos_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code_lf)

print("Updated pos_screen.dart successfully")
