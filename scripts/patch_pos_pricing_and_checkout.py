pos_path = r'C:\POS\client\lib\presentation\screens\pos_screen.dart'
with open(pos_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add import for unified_pricing_dialog.dart
import_target = "import '../widgets/edit_service_line_dialog.dart';"
import_replacement = """import '../widgets/edit_service_line_dialog.dart';
import '../widgets/unified_pricing_dialog.dart';"""
content = content.replace(import_target, import_replacement)

# 2. Update _triggerCheckout logic to use CheckoutResult and await
old_checkout_start = "    showDialog<double>(\n      context: context,\n      barrierDismissible: false,\n      builder: (_) => CheckoutDialog(\n        cartController: widget.cartController,\n        corteCajaId: activeShiftId,\n      ),\n    ).then((cambio) {"
# Let's inspect where .then((cambio) { finishes
import re

# Match showDialog<double>(...) up to the end of then block
old_checkout_pattern = r"    showDialog<double>\([\s\S]+?widget\.printerService\.printSaleTicketAsync\([\s\S]+?\}\);\s+\}\);\s+\}"

new_checkout_code = """    final checkoutResult = await showDialog<CheckoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        cartController: widget.cartController,
        corteCajaId: activeShiftId,
      ),
    );

    if (checkoutResult != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cobro Exitoso. Cambio: \$${checkoutResult.cambio.toStringAsFixed(2)}'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 3),
        ),
      );

      final folioTicket = 'TK-${DateTime.now().millisecondsSinceEpoch.toString().safeSub(7)}';

      final ticketData = TicketPrintData(
        negocioNombre: widget.nombreNegocio,
        folio: folioTicket,
        fecha: DateTime.now(),
        cajero: widget.authController.currentUser?.nombre ?? widget.usuarioId,
        turnoId: activeShiftId,
        items: currentItemsSnapshot,
        subtotal: currentSubtotal,
        descuentoTotal: currentDescuento,
        total: checkoutResult.totalFinal,
        ajusteRedondeo: checkoutResult.ajusteRedondeo,
        pagos: checkoutResult.pagos.isNotEmpty
            ? checkoutResult.pagos
            : [
                PaymentMethodBreakdown(metodo: 'Liquidado', monto: checkoutResult.totalFinal),
              ],
        cambio: checkoutResult.cambio,
      );

      final res = await widget.printerService.printSaleTicketAsync(
        ticketData,
        openCashDrawer: true,
      );

      if (mounted) {
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.message), backgroundColor: const Color(0xFF2E7D32)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: Colors.orange.shade800,
              action: res.plainTextTicket != null
                  ? SnackBarAction(
                      label: 'Ver Ticket',
                      textColor: Colors.white,
                      onPressed: () {
                        PrinterService.showThermalPreviewDialog(context, res.plainTextTicket!);
                      },
                    )
                  : null,
            ),
          );
        }
      }
    }

    _refocusSearch();
  }"""

content, n_ch = re.subn(old_checkout_pattern, new_checkout_code, content)
print(f"Replaced _triggerCheckout: {n_ch}")

# 3. Replace _showPriceTierMenu with UnifiedPricingDialog
old_tier_menu_pattern = r"  Future<void> _showPriceTierMenu\(SaleDetailItem item\) async \{[\s\S]+?_refocusSearch\(\);\s+\}"
new_tier_menu_code = """  Future<void> _showPriceTierMenu(SaleDetailItem item) async {
    if (item.productoId == 'ART-COMUN') return;

    final prod = await widget.cartController.salesRepository.findProductById(item.productoId) ??
        await widget.cartController.salesRepository.findProductByBarcodeOrSku(item.sku ?? item.productoId);
    if (!mounted) return;

    await UnifiedPricingDialog.show(
      context: context,
      cartController: widget.cartController,
      item: item,
      product: prod,
      isGlobal: false,
    );
    _refocusSearch();
  }"""

content, n_tm = re.subn(old_tier_menu_pattern, new_tier_menu_code, content)
print(f"Replaced _showPriceTierMenu: {n_tm}")

# 4. Replace P. UNIT header PopupMenuButton with UnifiedPricingDialog.show
old_header_pattern = r"                    SizedBox\(\s+width: 95,\s+child: PopupMenuButton<String>\([\s\S]+?child: Container\(\s+padding: const EdgeInsets\.symmetric\(horizontal: 6, vertical: 3\),[\s\S]+?\}\),\s+\)\s+\),\s+\),"
new_header_code = """                    SizedBox(
                      width: 95,
                      child: Tooltip(
                        message: 'Cambiar Nivel o Descuento Global a todo el Ticket',
                        child: InkWell(
                          onTap: () async {
                            await UnifiedPricingDialog.show(
                              context: context,
                              cartController: widget.cartController,
                              isGlobal: true,
                            );
                            _refocusSearch();
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'P. UNIT ',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                Text(
                                  '[${widget.cartController.currentGlobalTier} ▾]',
                                  style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),"""

content, n_hd = re.subn(old_header_pattern, new_header_code, content)
print(f"Replaced P. UNIT header: {n_hd}")

# 5. Replace P. UNIT row cell with compact pricing display
old_row_cell_pattern = r"                          // P\. Unitario[\s\S]+?onTap: \(\) => _showPriceTierMenu\(item\),[\s\S]+?child: Container\([\s\S]+?Text\(\s+item\.etiquetaPrecio,[\s\S]+?\),\s+\),\s+\),\s+\),"
new_row_cell_code = """                          // P. Unitario con Gestor Unificado PopOver
                          SizedBox(
                            width: 95,
                            child: InkWell(
                              onTap: () => _showPriceTierMenu(item),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.blueGrey.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          '\$${(item.cantidad > 0 ? (item.totalLinea / item.cantidad) : item.precioHistorico).toStringAsFixed(2)}',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.arrow_drop_down, size: 14, color: Colors.blueGrey),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: item.etiquetaPrecio.contains('Cerrajero')
                                            ? const Color(0xFF0D47A1)
                                            : item.etiquetaPrecio.contains('Taller')
                                                ? const Color(0xFF4A148C)
                                                : item.etiquetaPrecio.contains('Mayoreo')
                                                    ? const Color(0xFFE65100)
                                                    : item.etiquetaPrecio.contains('Manual')
                                                        ? const Color(0xFF37474F)
                                                        : const Color(0xFF2E7D32),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        item.etiquetaPrecio,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),"""

content, n_rc = re.subn(old_row_cell_pattern, new_row_cell_code, content)
print(f"Replaced P. UNIT row cell: {n_rc}")

with open(pos_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print("Updated pos_screen.dart successfully")
