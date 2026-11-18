pos_path = r'C:\POS\client\lib\presentation\screens\pos_screen.dart'
with open(pos_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 1. Replace _triggerCheckout showDialog (lines 538-606, 0-indexed: 537-606)
print("Line 538:", repr(lines[537]))
print("Line 606:", repr(lines[605]))

new_checkout_lines = [
"""    final checkoutResult = await showDialog<CheckoutResult>(
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

      // Disparar sincronización inmediata de la venta y actualizar alertas
      widget.syncWorker.triggerSyncNow();
      widget.alertsController.loadAlerts(silent: true);
    }

    _refocusSearch();
  }
"""
]

# We reconstruct the file with lines
lines = lines[:537] + new_checkout_lines + lines[607:]

content = "".join(lines)

# 2. Replace Header
old_header = """                    SizedBox(
                      width: 95,
                      child: Tooltip(
                        message: 'Cambiar Nivel de Precio Masivo a Todo el Ticket',
                        child: PopupMenuButton<String>(
                          tooltip: '',
                          initialValue: widget.cartController.currentGlobalTier,
                          onSelected: (tier) {
                            widget.cartController.applyGlobalPriceTier(tier);
                            _refocusSearch();
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'Público',
                              child: Row(
                                children: [
                                  Icon(Icons.people, size: 16, color: Color(0xFF2E7D32)),
                                  SizedBox(width: 8),
                                  Text('Público Casual'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Cerrajero',
                              child: Row(
                                children: [
                                  Icon(Icons.vpn_key, size: 16, color: Color(0xFF0D47A1)),
                                  SizedBox(width: 8),
                                  Text('Colega Cerrajero'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Taller',
                              child: Row(
                                children: [
                                  Icon(Icons.build, size: 16, color: Color(0xFF4A148C)),
                                  SizedBox(width: 8),
                                  Text('Taller Automotriz'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Mayoreo',
                              child: Row(
                                children: [
                                  Icon(Icons.layers, size: 16, color: Color(0xFFE65100)),
                                  SizedBox(width: 8),
                                  Text('Precio Mayoreo'),
                                ],
                              ),
                            ),
                          ],
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

new_header = """                    SizedBox(
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

content = content.replace(old_header, new_header)

# 3. Replace Row Cell
old_row_cell = """                          // Precio Unitario Interactivo con Selector de Nivel
                          SizedBox(
                            width: 130,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _showPriceTierMenu(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                                          '\$${item.precioHistorico.toStringAsFixed(2)}',
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
                                        color: item.etiquetaPrecio == 'Cerrajero'
                                            ? const Color(0xFF0D47A1)
                                            : item.etiquetaPrecio == 'Taller'
                                                ? const Color(0xFF4A148C)
                                                : item.etiquetaPrecio == 'Mayoreo'
                                                    ? const Color(0xFFE65100)
                                                    : const Color(0xFF2E7D32),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        item.etiquetaPrecio,
                                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),"""

new_row_cell = """                          // P. Unitario con Gestor Unificado PopOver
                          SizedBox(
                            width: 110,
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

content = content.replace(old_row_cell, new_row_cell)

with open(pos_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)

print("Exact replacement completed successfully!")
