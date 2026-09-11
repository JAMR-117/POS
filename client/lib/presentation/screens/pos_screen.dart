import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';
import '../widgets/checkout_dialog.dart';
import 'dart:async';
import '../widgets/sync_status_badge.dart';
import '../../data/sync/sync_worker.dart';

// Definición de Intenciones para Atajos de Teclado
class FocusSearchIntent extends Intent { const FocusSearchIntent(); }
class CheckoutIntent extends Intent { const CheckoutIntent(); }
class HoldSaleIntent extends Intent { const HoldSaleIntent(); }
class ViewHeldSalesIntent extends Intent { const ViewHeldSalesIntent(); }
class ClearCartIntent extends Intent { const ClearCartIntent(); }

class PosScreen extends StatefulWidget {
  final CartController cartController;
  final String corteCajaId;
  final SyncWorker syncWorker;

  const PosScreen({
    super.key,
    required this.cartController,
    required this.syncWorker, 
    this.corteCajaId = 'corte-demo-001',
  });

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _refocusSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Mantiene anclado el foco en la barra de escaneo sin fricciones
  void _refocusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_searchFocusNode.hasFocus && mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _handleBarcodeScan(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;

    _searchController.clear();
    final results = await widget.cartController.scanOrSearchProduct(text);

    if (results.length > 1 && mounted) {
      _showIncrementalSearchResults(results);
    }

    // Auto-scroll al final del ticket
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      _refocusSearch();
    });
  }

  void _showIncrementalSearchResults(List<Product> products) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coincidencias encontradas', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 500,
          height: 300,
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, idx) {
              final prod = products[idx];
              return ListTile(
                dense: true,
                title: Text(prod.descripcion, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('SKU: ${prod.sku ?? "N/A"} | Stock: ${prod.stockActual}'),
                trailing: Text('\$${prod.precioVenta.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  widget.cartController.addProduct(prod);
                  Navigator.of(ctx).pop();
                  _refocusSearch();
                },
              );
            },
          ),
        ),
      ),
    ).then((_) => _refocusSearch());
  }

  void _triggerCheckout() {
    if (widget.cartController.isEmpty) return;

    showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        cartController: widget.cartController,
        corteCajaId: widget.corteCajaId,
      ),
    ).then((cambio) {
      if (cambio != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cobro Exitoso. Cambio: \$${cambio.toStringAsFixed(2)}'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _refocusSearch();
    });
  }

  void _showHeldSalesModal() {
    final held = widget.cartController.heldSales;
    if (held.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay ventas en espera.'), duration: Duration(seconds: 2)),
      );
      _refocusSearch();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tickets en Espera', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 450,
          height: 250,
          child: ListView.builder(
            itemCount: held.length,
            itemBuilder: (c, idx) {
              final sale = held[idx];
              final total = sale.items.fold<double>(0.0, (acc, it) => acc + (it.totalLinea ?? 0.0));
              return ListTile(
                dense: true,
                leading: const Icon(Icons.pause_circle_outline, color: Color(0xFF1F4E79)),
                title: Text('Venta #${idx + 1} (${sale.items.length} artículos)'),
                subtitle: Text('Pausado: ${sale.heldAt.hour}:${sale.heldAt.minute.toString().padLeft(2, '0')}'),
                trailing: Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  widget.cartController.resumeSale(idx);
                  Navigator.of(ctx).pop();
                  _refocusSearch();
                },
              );
            },
          ),
        ),
      ),
    ).then((_) => _refocusSearch());
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.f1): const FocusSearchIntent(),
        const SingleActivator(LogicalKeyboardKey.f6): const HoldSaleIntent(),
        const SingleActivator(LogicalKeyboardKey.f7): const ViewHeldSalesIntent(),
        const SingleActivator(LogicalKeyboardKey.f12): const CheckoutIntent(),
        const SingleActivator(LogicalKeyboardKey.delete, alt: true): const ClearCartIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(onInvoke: (_) => _refocusSearch()),
          HoldSaleIntent: CallbackAction<HoldSaleIntent>(onInvoke: (_) {
            widget.cartController.holdCurrentSale();
            _refocusSearch();
            return null;
          }),
          ViewHeldSalesIntent: CallbackAction<ViewHeldSalesIntent>(onInvoke: (_) {
            _showHeldSalesModal();
            return null;
          }),
          CheckoutIntent: CallbackAction<CheckoutIntent>(onInvoke: (_) {
            _triggerCheckout();
            return null;
          }),
          ClearCartIntent: CallbackAction<ClearCartIntent>(onInvoke: (_) {
            widget.cartController.clearCart();
            _refocusSearch();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFECEFF1),
            body: SafeArea(
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
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BARRA SUPERIOR DE ENTRADA / ESCÁNER
  // ---------------------------------------------------------------------------
  Widget _buildHeaderBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.go,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Escanea código de barras o escribe descripción y presiona [ENTER]...',
                prefixIcon: Icon(Icons.qr_code_scanner, color: Color(0xFF1F4E79)),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9FAFB),
              ),
              onSubmitted: _handleBarcodeScan,
            ),
          ),
          const SizedBox(width: 12),
          SyncStatusBadge(syncWorker: widget.syncWorker),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA VISOR DEL TICKET ACTIVO
  // ---------------------------------------------------------------------------
  Widget _buildActiveTicketTable() {
    return AnimatedBuilder(
      animation: widget.cartController,
      builder: (context, _) {
        final items = widget.cartController.items;

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.shopping_cart_outlined, size: 64, color: Color(0xFF9E9E9E)),
                SizedBox(height: 8),
                Text(
                  'El ticket está vacío\nEscanee un producto o use la barra de búsqueda',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF757575), fontSize: 15),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFCFD8DC)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Container(
                color: const Color(0xFF1F4E79),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                child: const Row(
                  children: [
                    SizedBox(width: 80, child: Text('CANT.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    Expanded(child: Text('DESCRIPCIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    SizedBox(width: 100, child: Text('P. UNIT', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    SizedBox(width: 100, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              item.cantidad.toStringAsFixed(item.cantidad % 1 == 0 ? 0 : 3),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.descripcion,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              '\$${item.precioHistorico.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              '\$${item.totalLinea.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Color(0xFFE53935)),
                              onPressed: () {
                                widget.cartController.removeItem(item.id);
                                _refocusSearch();
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PANEL DE LIQUIDACIÓN Y TOTALES (LATERAL)
  // ---------------------------------------------------------------------------
  Widget _buildRightLiquidationPanel() {
    return AnimatedBuilder(
      animation: widget.cartController,
      builder: (context, _) {
        final total = widget.cartController.total;
        final subtotal = widget.cartController.subtotal;
        final descuento = widget.cartController.descuentoTotal;

        return Container(
          margin: const EdgeInsets.only(top: 12.0, right: 12.0, bottom: 12.0),
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFCFD8DC)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('RESUMEN DE VENTA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF607D8B))),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal:', style: TextStyle(fontSize: 15)),
                  Text('\$${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Descuento:', style: TextStyle(fontSize: 15, color: Color(0xFF2E7D32))),
                  Text('-\$${descuento.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, color: Color(0xFF2E7D32))),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F4E79),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL A PAGAR', style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: widget.cartController.isEmpty ? null : _triggerCheckout,
                child: const Text(
                  'COBRAR [F12]',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER DE ACCIONES RÁPIDAS Y ATAJOS DE TECLADO
  // ---------------------------------------------------------------------------
  Widget _buildKeyboardShortcutsFooter() {
    return Container(
      color: const Color(0xFF263238),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _buildKeyBadge('F1', 'Buscador', () => _refocusSearch()),
          _buildKeyBadge('F6', 'Pausar Ticket', () {
            widget.cartController.holdCurrentSale();
            _refocusSearch();
          }),
          _buildKeyBadge('F7', 'Ver Pausados (${widget.cartController.heldSales.length})', _showHeldSalesModal),
          _buildKeyBadge('Alt+Supr', 'Limpiar', () {
            widget.cartController.clearCart();
            _refocusSearch();
          }),
          _buildKeyBadge('F12', 'Cobrar', _triggerCheckout),
        ],
      ),
    );
  }

  Widget _buildKeyBadge(String keyLabel, String actionLabel, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF37474F),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                keyLabel,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              actionLabel,
              style: const TextStyle(color: Color(0xFFECEFF1), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}