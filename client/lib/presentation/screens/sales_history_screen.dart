import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/local/models.dart';
import '../../data/repositories/sales_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/admin_auth_dialog.dart';

class SalesHistoryScreen extends StatefulWidget {
  final AuthController authController;
  final PrinterService? printerService;
  final String? activeShiftId;

  const SalesHistoryScreen({
    super.key,
    required this.authController,
    this.printerService,
    this.activeShiftId,
  });

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final SalesRepository _salesRepo = SalesRepository();
  final TextEditingController _searchController = TextEditingController();

  List<SaleRecord> _sales = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    try {
      final results = await _salesRepo.getSalesHistory(query: _searchController.text);
      if (!mounted) return;
      setState(() => _sales = results);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reprintTicket(SaleRecord sale, List<SaleDetailItem> details) async {
    if (widget.printerService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio de impresión no configurado.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final ticketData = TicketPrintData(
      negocioNombre: 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ',
      folio: '${sale.folioTicket} (COPIA REIMPRESA)',
      fecha: sale.fechaVenta,
      cajero: widget.authController.currentUser?.nombre ?? 'Cajero',
      turnoId: 'HISTORIAL',
      items: details,
      subtotal: sale.total,
      descuentoTotal: 0.0,
      total: sale.total,
      pagos: [PaymentMethodBreakdown(metodo: 'Liquidado', monto: sale.total)],
      cambio: 0.0,
    );

    final res = await widget.printerService!.printSaleTicketAsync(ticketData, openCashDrawer: false);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: const Color(0xFF2E7D32)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: Colors.orange.shade800),
      );
      if (res.plainTextTicket != null) {
        PrinterService.showThermalPreviewDialog(context, res.plainTextTicket!);
      }
    }
  }

  Future<void> _confirmCancelFullTicket(SaleRecord sale, List<SaleDetailItem> details) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar Ticket ${sale.folioTicket}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¿Estás seguro de cancelar por completo este ticket?\n\nSe reintegrarán automáticamente al inventario todos los productos físicos e insumos consumidos en servicios:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ...details.where((d) => d.cantidad > 0).map((d) {
                final insumoNote = d.hasDynamicInsumo
                    ? ' -> Reintegra ${d.cantidadInsumoConsumida.toStringAsFixed(d.cantidadInsumoConsumida % 1 == 0 ? 0 : 2)}x ${d.insumoUtilizadoSku ?? d.insumoUtilizadoId}'
                    : (!d.esServicio ? ' -> Reintegra ${d.cantidad.toStringAsFixed(d.cantidad % 1 == 0 ? 0 : 2)} pzs' : '');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${d.nombre}$insumoNote', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Cancelar Ticket'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final isAuthorized = await AdminAuthDialog.requestAdminAccess(context, widget.authController);
    if (!isAuthorized || !mounted) return;

    try {
      await _salesRepo.cancelSale(sale.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket cancelado y existencias/insumos reintegrados al inventario.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        _loadSales();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cancelar ticket: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openPartialRefundDialog(SaleRecord sale, List<SaleDetailItem> details) async {
    final Map<String, double> refundQuantities = {};
    for (final it in details) {
      refundQuantities[it.id] = 0.0;
    }
    final motivoCtrl = TextEditingController(text: 'Cliente solicitó cambio o devolución');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final double totalADevolver = details.fold(0.0, (acc, it) {
            final qty = refundQuantities[it.id] ?? 0.0;
            return acc + (qty * it.precioHistorico);
          });

          return AlertDialog(
            title: Text('Devolución de Artículos - Folio: ${sale.folioTicket}'),
            content: SizedBox(
              width: 560,
              height: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Selecciona las unidades a devolver para reintegrar automáticamente productos o insumos de servicios al inventario:',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: details.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = details[idx];
                        final double currentRefund = refundQuantities[item.id] ?? 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text(
                                      'Comprado: ${item.cantidad} | P.U: \$${item.precioHistorico.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    if (item.hasDynamicInsumo)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '🔑 Insumo vinculado: ${item.cantidadInsumoConsumida.toStringAsFixed(item.cantidadInsumoConsumida % 1 == 0 ? 0 : 2)}x ${item.insumoUtilizadoSku ?? item.insumoUtilizadoId} (se reintegrará a stock)',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF006064)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: currentRefund > 0
                                        ? () => setModalState(() => refundQuantities[item.id] = currentRefund - 1.0)
                                        : null,
                                  ),
                                  Text(
                                    currentRefund.toStringAsFixed(item.cantidad % 1 != 0 ? 1 : 0),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: currentRefund < item.cantidad
                                        ? () => setModalState(() => refundQuantities[item.id] = currentRefund + 1.0)
                                        : null,
                                  ),
                                ],
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '\$${(currentRefund * item.precioHistorico).toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de la devolución *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total a Reembolsar al Cliente:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '\$${totalADevolver.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                onPressed: totalADevolver > 0 ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Confirmar Devolución'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      final List<Map<String, dynamic>> itemsToRefund = [];
      refundQuantities.forEach((detId, qty) {
        if (qty > 0) {
          itemsToRefund.add({'detalle_id': detId, 'cantidad': qty});
        }
      });

      if (itemsToRefund.isEmpty) return;

      final isAuthorized = await AdminAuthDialog.requestAdminAccess(context, widget.authController);
      if (!isAuthorized || !mounted) return;

      try {
        await _salesRepo.refundSaleItems(
          ventaId: sale.id,
          itemsToRefund: itemsToRefund,
          motivo: motivoCtrl.text.trim(),
          usuarioId: widget.authController.currentUser?.nombre ?? 'cajero',
          corteCajaId: widget.activeShiftId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Devolución procesada. Stock e insumos reintegrados al inventario con éxito.'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
          _loadSales();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error en devolución: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showTicketDetails(SaleRecord sale) async {
    final details = await _salesRepo.getSaleDetails(sale.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ticket: ${sale.folioTicket}'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.fechaVenta.toLocal())}',
                style: const TextStyle(color: Colors.grey),
              ),
              const Divider(),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: details.length,
                  itemBuilder: (_, i) {
                    final item = details[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item.cantidad} x \$${item.precioHistorico.toStringAsFixed(2)}'),
                          if (item.hasDynamicInsumo)
                            Text(
                              '🔑 Insumo descontado: ${item.cantidadInsumoConsumida.toStringAsFixed(item.cantidadInsumoConsumida % 1 == 0 ? 0 : 2)}x ${item.insumoUtilizadoSku ?? item.insumoUtilizadoId}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF006064), fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                      trailing: Text('\$${item.totalLinea.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
              const Divider(),
              Text(
                'TOTAL: \$${sale.total.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Reimprimir Ticket'),
            onPressed: () {
              Navigator.pop(ctx);
              _reprintTicket(sale, details);
            },
          ),
          if (sale.estatus != 'cancelado') ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB71C1C), side: const BorderSide(color: Color(0xFFB71C1C))),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar Ticket'),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmCancelFullTicket(sale, details);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
              icon: const Icon(Icons.undo),
              label: const Text('Devolver Artículos'),
              onPressed: () {
                Navigator.pop(ctx);
                _openPartialRefundDialog(sale, details);
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Tickets y Devoluciones'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Escanear código del ticket o buscar folio...',
                prefixIcon: Icon(Icons.receipt_long),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: (_) => _loadSales(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _sales.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      final isCanceled = sale.estatus == 'cancelado';

                      return ListTile(
                        tileColor: isCanceled ? Colors.red.shade50 : Colors.white,
                        leading: CircleAvatar(
                          backgroundColor: isCanceled ? Colors.red.shade100 : const Color(0xFFE3F2FD),
                          child: Icon(
                            isCanceled ? Icons.block : Icons.check_circle,
                            color: isCanceled ? Colors.red : const Color(0xFF1F4E79),
                          ),
                        ),
                        title: Text(
                          sale.folioTicket,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: isCanceled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(sale.fechaVenta.toLocal())),
                        trailing: Text(
                          '\$${sale.total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isCanceled ? Colors.red : Colors.green.shade800,
                          ),
                        ),
                        onTap: () => _showTicketDetails(sale),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
