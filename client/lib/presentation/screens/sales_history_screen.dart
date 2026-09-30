import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/sales_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/admin_auth_dialog.dart';

class SalesHistoryScreen extends StatefulWidget {
  final AuthController authController;

  const SalesHistoryScreen({super.key, required this.authController});

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
              )
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.fechaVenta.toLocal())}', style: const TextStyle(color: Colors.grey)),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: details.length,
                  itemBuilder: (_, i) {
                    final item = details[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.descripcion),
                      subtitle: Text('${item.cantidad} x \$${item.precioHistorico.toStringAsFixed(2)}'),
                      trailing: Text('\$${item.totalLinea.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  },
                ),
              ),
              const Divider(),
              Text('TOTAL: \$${sale.total.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (sale.estatus != 'cancelado')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
              icon: const Icon(Icons.cancel_presentation),
              label: const Text('Cancelar Venta y Reintegrar Stock'),
              onPressed: () async {
                final isAuthorized = await AdminAuthDialog.requestAdminAccess(context, widget.authController);
                if (!isAuthorized) return;

                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (confirmCtx) => AlertDialog(
                    title: const Text('Confirmar Cancelación'),
                    content: const Text('Esta acción revertirá el pago y regresará la mercancía al inventario local. No se puede deshacer.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('No, volver')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(confirmCtx, true), 
                        child: const Text('Sí, Cancelar Ticket')
                      ),
                    ],
                  )
                );

                if (confirm == true) {
                  try {
                    await _salesRepo.cancelSale(sale.id);
                    if (mounted) {
                      Navigator.pop(ctx);
                      _loadSales();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket cancelado exitosamente'), backgroundColor: Color(0xFF2E7D32)));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
            )
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
                          child: Icon(isCanceled ? Icons.block : Icons.check_circle, color: isCanceled ? Colors.red : const Color(0xFF1F4E79)),
                        ),
                        title: Text(sale.folioTicket, style: TextStyle(fontWeight: FontWeight.bold, decoration: isCanceled ? TextDecoration.lineThrough : null)),
                        subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(sale.fechaVenta.toLocal())),
                        trailing: Text(
                          '\$${sale.total.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isCanceled ? Colors.red : Colors.green.shade800),
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