import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Modelos y Repositorios Locales
import '../../core/department_theme.dart';
import '../../core/string_utils.dart';
import '../../data/local/models.dart';
import '../../data/sync/sync_worker.dart';
import '../../data/inventory/inventory_api_client.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/repositories/product_repository.dart';

// Controladores
import '../controllers/cart_controller.dart';
import '../controllers/alerts_controller.dart';
import '../controllers/shift_controller.dart';
import '../controllers/auth_controller.dart';

// Pantallas y Widgets
import 'inventory_screen.dart';
import 'login_screen.dart';
import 'sales_history_screen.dart';
import 'clients_screen.dart';
import 'settings_screen.dart';
import '../widgets/checkout_dialog.dart';
import '../widgets/quote_dialog.dart';
import '../widgets/sync_status_badge.dart';
import '../widgets/stock_alerts_button.dart';
import '../widgets/shift_cut_dialog.dart';
import '../widgets/open_shift_dialog.dart';
import '../widgets/common_article_dialog.dart';
import '../widgets/quick_product_form_dialog.dart';
import '../widgets/client_selection_dialog.dart';
import '../widgets/advanced_product_search_dialog.dart';
import '../widgets/cash_movement_dialog.dart';
import '../widgets/insufficient_stock_dialog.dart';
import '../widgets/product_or_service_action_dialog.dart';
import '../widgets/edit_service_line_dialog.dart';

// ---------------------------------------------------------------------------
// DECLARACIÓN DE INTENCIONES PARA ATAJOS DE TECLADO
// ---------------------------------------------------------------------------
class FocusSearchIntent extends Intent { const FocusSearchIntent(); }
class AdvancedSearchIntent extends Intent { const AdvancedSearchIntent(); }
class CheckoutIntent extends Intent { const CheckoutIntent(); }
class HoldSaleIntent extends Intent { const HoldSaleIntent(); }
class ViewHeldSalesIntent extends Intent { const ViewHeldSalesIntent(); }
class ClearCartIntent extends Intent { const ClearCartIntent(); }
class OpenInventoryIntent extends Intent { const OpenInventoryIntent(); }
class ShiftCutIntent extends Intent { const ShiftCutIntent(); }
class QuoteIntent extends Intent { const QuoteIntent(); }
class CommonArticleIntent extends Intent { const CommonArticleIntent(); }
class CashMovementIntent extends Intent { const CashMovementIntent(); }
class SalesHistoryIntent extends Intent { const SalesHistoryIntent(); }

class PosScreen extends StatefulWidget {
  final CartController cartController;
  final SyncWorker syncWorker;
  final AlertsController alertsController;
  final ShiftController shiftController;
  final InventoryApiClient inventoryApiClient;
  final PrinterService printerService;
  final AuthController authController;
  final String usuarioId;
  final String nombreNegocio;

  const PosScreen({
    super.key,
    required this.cartController,
    required this.syncWorker,
    required this.alertsController,
    required this.shiftController,
    required this.inventoryApiClient,
    required this.printerService,
    required this.authController,
    this.usuarioId = 'cajero-principal',
    this.nombreNegocio = 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ',
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
    widget.alertsController.loadAlerts(silent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.shiftController.checkActiveShift();
      if (!widget.shiftController.hasActiveShift && mounted) {
        await OpenShiftDialog.show(context, widget.shiftController);
        _refocusSearch();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Mantiene anclado el foco en la barra de búsqueda / escáner
  void _refocusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final modalRoute = ModalRoute.of(context);
      if (modalRoute != null && !modalRoute.isCurrent) return;
      if (!_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  /// Flujo interactivo Fase 4: Al seleccionar cualquier artículo del catálogo o [F1],
  /// si es un Producto Físico despliega `ProductOrServiceActionDialog` ("Solo Producto [Enter]" vs "Aplicar Servicio").
  Future<void> _handleSelectedCatalogItem(Product product) async {
    if (product.esServicio || product.id == 'ART-COMUN') {
      await _tryAddProduct(product);
      return;
    }

    final double reservedInCart = widget.cartController.getReservedQuantityInCart(product.id);
    if (!mounted) return;

    final result = await ProductOrServiceActionDialog.show(
      context: context,
      product: product,
      salesRepository: widget.cartController.salesRepository,
      initialClientTier: widget.cartController.selectedClientTier,
      reservedInCart: reservedInCart,
    );

    if (result == null || !mounted) {
      _refocusSearch();
      return;
    }

    if (result.isDirectProduct) {
      await _tryAddProduct(product, quantity: 1.0);
      return;
    }

    final service = result.selectedService;
    if (service == null) {
      _refocusSearch();
      return;
    }

    final double insumoQty = result.insumoQuantityToDeduct;
    final double totalRequired = reservedInCart + insumoQty;

    // Validación Soft-Stop del stock físico de la llave/insumo utilizado
    if (insumoQty > 0 && totalRequired > product.stockActual) {
      if (!mounted) return;
      final decision = await InsufficientStockDialog.show(
        context: context,
        productName: '${product.nombre} (Insumo para ${service.nombre})',
        currentStock: product.stockActual,
        requestedQuantity: totalRequired,
        location: product.ubicacion,
      );

      if (decision == InsufficientStockDecision.allowNegative) {
        widget.cartController.addDynamicServiceItem(
          service: service,
          insumo: product,
          precioCobrado: result.servicePrice,
          etiquetaPrecio: result.priceTierLabel,
          cantidadInsumoConsumida: insumoQty,
        );
      } else if (decision == InsufficientStockDecision.adjustToLimit) {
        final double remaining = product.stockActual - reservedInCart;
        if (remaining <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Operación cancelada: Sin existencias disponibles de "${product.nombre}" para el servicio.'),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          widget.cartController.addDynamicServiceItem(
            service: service,
            insumo: product,
            precioCobrado: result.servicePrice,
            etiquetaPrecio: result.priceTierLabel,
            cantidadInsumoConsumida: remaining,
          );
        }
      }
    } else {
      widget.cartController.addDynamicServiceItem(
        service: service,
        insumo: product,
        precioCobrado: result.servicePrice,
        etiquetaPrecio: result.priceTierLabel,
        cantidadInsumoConsumida: insumoQty,
      );
    }

    _refocusSearch();
  }

  Future<void> _tryAddProduct(Product product, {double quantity = 1.0}) async {
    final existingIndex = widget.cartController.items.indexWhere(
      (i) => i.productoId == product.id && !i.hasDynamicInsumo,
    );
    final double currentInCart = product.esServicio
        ? (existingIndex != -1 ? widget.cartController.items[existingIndex].cantidad : 0.0)
        : widget.cartController.getReservedQuantityInCart(product.id);
    final double targetTotal = currentInCart + quantity;

    final effectiveStock = await widget.cartController.getEffectiveStockForProduct(product);

    if (effectiveStock != double.infinity && targetTotal > effectiveStock) {
      if (!mounted) return;
      final decision = await InsufficientStockDialog.show(
        context: context,
        productName: product.nombre,
        currentStock: effectiveStock,
        requestedQuantity: targetTotal,
        location: product.ubicacion,
      );

      if (decision == InsufficientStockDecision.allowNegative) {
        widget.cartController.addProduct(product, quantity: quantity);
      } else if (decision == InsufficientStockDecision.adjustToLimit) {
        final double otherReserved = !product.esServicio
            ? (currentInCart - (existingIndex != -1 ? widget.cartController.items[existingIndex].cantidad : 0.0))
            : 0.0;
        final double maxDirectAllowed = effectiveStock - otherReserved;

        if (maxDirectAllowed <= 0) {
          if (existingIndex != -1) {
            widget.cartController.removeItem(widget.cartController.items[existingIndex].id);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Operación cancelada: No se agregó "${product.nombre}" por falta de existencias.'),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (existingIndex != -1) {
            widget.cartController.updateQuantity(widget.cartController.items[existingIndex].id, maxDirectAllowed);
          } else {
            widget.cartController.addProduct(product, quantity: maxDirectAllowed);
          }
        }
      }
    } else {
      widget.cartController.addProduct(product, quantity: quantity);
    }
    _refocusSearch();
  }

  Future<void> _tryUpdateQuantity(SaleDetailItem item, double newQuantity) async {
    if (newQuantity <= 0) {
      widget.cartController.removeItem(item.id);
      _refocusSearch();
      return;
    }

    // Si es un servicio con insumo dinámico vinculado, validar el stock físico de la llave
    if (item.hasDynamicInsumo) {
      final insumoId = item.insumoUtilizadoId!;
      Product? insumo = widget.cartController.getProductFromCache(insumoId);
      if (insumo == null) {
        insumo = await widget.cartController.salesRepository.findProductById(insumoId);
        if (insumo != null) widget.cartController.cacheProduct(insumo);
      }
      final double stockInsumo = insumo?.stockActual ?? item.stockDisponible;
      final double factor = item.cantidad > 0 ? (item.cantidadInsumoConsumida / item.cantidad) : 1.0;
      final double projectedLineInsumo = newQuantity * factor;
      final double otherReserved =
          widget.cartController.getReservedQuantityInCart(insumoId) - item.cantidadInsumoConsumida;
      final double totalRequired = otherReserved + projectedLineInsumo;

      if (factor > 0 && totalRequired > stockInsumo) {
        if (!mounted) return;
        final decision = await InsufficientStockDialog.show(
          context: context,
          productName: '${item.insumoUtilizadoNombre ?? insumoId} (Insumo)',
          currentStock: stockInsumo,
          requestedQuantity: totalRequired,
          location: item.ubicacion,
        );

        if (decision == InsufficientStockDecision.allowNegative) {
          widget.cartController.updateQuantity(item.id, newQuantity);
        } else if (decision == InsufficientStockDecision.adjustToLimit) {
          final double maxInsumoForLine = stockInsumo - otherReserved;
          final double maxServiceQty = factor > 0 ? (maxInsumoForLine / factor).floorToDouble() : newQuantity;
          if (maxServiceQty <= 0) {
            widget.cartController.removeItem(item.id);
          } else {
            widget.cartController.updateQuantity(item.id, maxServiceQty);
          }
        }
      } else {
        widget.cartController.updateQuantity(item.id, newQuantity);
      }
      _refocusSearch();
      return;
    }

    Product? prod = widget.cartController.getProductFromCache(item.productoId);
    if (prod == null) {
      prod = await widget.cartController.salesRepository.findProductById(item.productoId);
      if (prod != null) widget.cartController.cacheProduct(prod);
    }

    final double effectiveStock = prod != null
        ? await widget.cartController.getEffectiveStockForProduct(prod)
        : item.stockDisponible;

    if (effectiveStock != double.infinity && newQuantity > effectiveStock) {
      if (!mounted) return;
      final decision = await InsufficientStockDialog.show(
        context: context,
        productName: item.nombre,
        currentStock: effectiveStock,
        requestedQuantity: newQuantity,
        location: item.ubicacion,
      );

      if (decision == InsufficientStockDecision.allowNegative) {
        widget.cartController.updateQuantity(item.id, newQuantity);
      } else if (decision == InsufficientStockDecision.adjustToLimit) {
        if (effectiveStock <= 0) {
          widget.cartController.removeItem(item.id);
        } else {
          widget.cartController.updateQuantity(item.id, effectiveStock);
        }
      }
    } else {
      widget.cartController.updateQuantity(item.id, newQuantity);
    }
    _refocusSearch();
  }

  Future<void> _tryIncrementQuantity(SaleDetailItem item) async {
    await _tryUpdateQuantity(item, item.cantidad + 1.0);
  }

  Future<void> _tryIncrementLastItem() async {
    if (widget.cartController.items.isNotEmpty) {
      await _tryIncrementQuantity(widget.cartController.items.last);
    }
  }

  Future<void> _handleBarcodeScan(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;

    _searchController.clear();

    // Consulta inteligente por código exacto, SKU o coincidencia con comodín %
    final results = await widget.cartController.scanOrSearchProduct(text);

    if (results.length > 1 && mounted) {
      _showIncrementalSearchResults(results);
    } else if (results.length == 1 && mounted) {
      await _handleSelectedCatalogItem(results.first);
    } else if (results.isEmpty && mounted) {
      final wantsToAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Producto no encontrado'),
          content: Text('El término o código "$text" no existe en el catálogo local.\n\n¿Deseas darlo de alta rápidamente?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true), 
              child: const Text('Agregar Producto'),
            ),
          ],
        ),
      );

      if (wantsToAdd == true && mounted) {
        final productRepo = ProductRepository(); 
        final newProduct = await QuickProductFormDialog.show(context, text, productRepo);
        
        if (newProduct != null && mounted) {
          await _handleSelectedCatalogItem(newProduct);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Producto guardado y agregado al ticket.'), backgroundColor: Colors.green),
            );
          }
        }
      }
    }
    
    _refocusSearch();
  }

  /// Despliega el modal de selección de coincidencias y variantes por molde
  void _showIncrementalSearchResults(List<Product> products) {
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
          child: ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, idx) {
              final prod = products[idx];
              final isService = prod.esServicio;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prod.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    if (prod.marca != null && prod.marca!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECEFF1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          prod.marca!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF37474F)),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 3),
                    Text(
                      prod.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DepartmentBadge(departamento: prod.departamento, compact: true),
                        if (prod.sku != null && prod.sku!.isNotEmpty)
                          Text('Clave/SKU: ${prod.sku}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1F4E79))),
                        if (prod.codigoEquivalencia != null && prod.codigoEquivalencia!.isNotEmpty)
                          Tooltip(
                            message: 'Ver todas las variantes del Molde: ${prod.codigoEquivalencia}',
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _openAdvancedProductSearch(initialQuery: 'molde:${prod.codigoEquivalencia}');
                                },
                                borderRadius: BorderRadius.circular(4),
                                hoverColor: const Color(0xFF1F4E79).withValues(alpha: 0.15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF1976D2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link, size: 12, color: Color(0xFF0D47A1)),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Molde: ${prod.codigoEquivalencia}',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (prod.ubicacion != null && prod.ubicacion!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Text('📍 ${prod.ubicacion}', style: TextStyle(fontSize: 11, color: Colors.brown.shade900, fontWeight: FontWeight.bold)),
                          ),
                        if (!isService)
                          Text('Stock: ${prod.stockActual}', style: TextStyle(fontSize: 11, color: prod.stockActual <= 5 ? Colors.red : Colors.green.shade800, fontWeight: FontWeight.bold))
                        else
                          const Text('⚙️ Servicio', style: TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${prod.precioVenta.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32)),
                    ),
                    if (prod.precioMayoreo != null && prod.cantidadMayoreo != null)
                      Text(
                        'Mayoreo: \$${prod.precioMayoreo!.toStringAsFixed(2)} (+${prod.cantidadMayoreo!.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      ),
                  ],
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _handleSelectedCatalogItem(prod);
                },
              );
            },
          ),
        ),
      ),
    ).then((_) => _refocusSearch());
  }

  void _openShiftCutModal() {
    ShiftCutDialog.show(context, widget.shiftController);
  }

  void _openInventoryView() {
    if (widget.authController.isAdmin) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InventoryScreen(
            apiClient: widget.inventoryApiClient,
            authController: widget.authController,
          ),
        ),
      ).then((_) => _refocusSearch());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acceso denegado: Se requiere rol de Administrador para abrir el Catálogo.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      _refocusSearch();
    }
  }

  /// Abre el modal de cotización digital (F8)
  void _openQuoteDialog() {
    if (widget.cartController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El ticket está vacío. Agrega artículos antes de cotizar.'),
          duration: Duration(seconds: 2),
        ),
      );
      _refocusSearch();
      return;
    }

    QuoteDialog.show(
      context,
      items: widget.cartController.items,
      subtotal: widget.cartController.subtotal,
      descuentoTotal: widget.cartController.descuentoTotal,
      total: widget.cartController.total,
      nombreNegocio: widget.nombreNegocio,
      clienteNombre: widget.cartController.selectedClientName,
    ).then((_) => _refocusSearch());
  }

  /// Diálogo ágil para edición manual exacta de cantidades
  Future<void> _showQuantityDialog(SaleDetailItem item) async {
    final controller = TextEditingController(
      text: item.cantidad.toStringAsFixed(item.cantidad % 1 == 0 ? 0 : 3),
    );

    final newQty = await showDialog<double>(
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
            child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
            decoration: const InputDecoration(
              labelText: 'Nueva Cantidad',
              border: OutlineInputBorder(),
              suffixText: 'piezas',
            ),
            onSubmitted: (val) {
              final parsed = double.tryParse(val);
              Navigator.pop(ctx, parsed);
            },
          ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              Navigator.pop(ctx, parsed);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (newQty != null) {
      await _tryUpdateQuantity(item, newQty);
    }
    _refocusSearch();
  }

  void _triggerCheckout() async {
    if (widget.cartController.isEmpty) return;

    if (!widget.shiftController.hasActiveShift) {
      final opened = await OpenShiftDialog.show(context, widget.shiftController);
      if (!opened) return;
    }

    if (!mounted) return;

    final currentItemsSnapshot = List<SaleDetailItem>.from(widget.cartController.items);
    final currentSubtotal = widget.cartController.subtotal;
    final currentDescuento = widget.cartController.descuentoTotal;
    final currentTotal = widget.cartController.total;
    final activeShiftId = widget.shiftController.activeShiftId;

    showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CheckoutDialog(
        cartController: widget.cartController,
        corteCajaId: activeShiftId,
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
          total: currentTotal,
          pagos: [
            PaymentMethodBreakdown(metodo: 'Liquidado', monto: currentTotal),
          ],
          cambio: cambio,
        );

        widget.printerService.printSaleTicketAsync(
          ticketData,
          openCashDrawer: true,
        ).then((res) {
          if (!mounted) return;
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
        });

        // Disparar sincronización inmediata de la venta y actualizar alertas
        widget.syncWorker.triggerSyncNow();
        widget.alertsController.loadAlerts(silent: true);
      }
      _refocusSearch();
    });
  }

  Future<void> _handleHoldSaleWithAlias() async {
    if (widget.cartController.isEmpty) return;

    final defaultAlias = 'Ticket #${widget.cartController.heldSales.length + 1} - ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    final aliasController = TextEditingController(text: defaultAlias);
    aliasController.selection = TextSelection(baseOffset: 0, extentOffset: defaultAlias.length);

    final alias = await showDialog<String>(
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
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nombre o referencia del ticket:\n(ej. Sr. Juan - Jetta Rojo, Mostrador 2)',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aliasController,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'Referencia / Nombre del cliente',
              ),
              onSubmitted: (val) {
                Navigator.of(ctx).pop(val.trim().isEmpty ? defaultAlias : val.trim());
              },
            ),
          ],
        ),
      ),
      ),
      actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar [Esc]'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = aliasController.text.trim();
              Navigator.of(ctx).pop(val.isEmpty ? defaultAlias : val);
            },
            child: const Text('Pausar Ticket [Enter]'),
          ),
        ],
      ),
    );

    if (alias != null && alias.isNotEmpty) {
      widget.cartController.holdCurrentSale(alias: alias);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Venta pausada como "$alias". Presiona F7 para reanudar.'),
            backgroundColor: const Color(0xFFE65100),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    _refocusSearch();
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
          child: ListView.separated(
            itemCount: held.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (c, idx) {
              final sale = held[idx];
              final total = sale.items.fold<double>(0.0, (acc, it) => acc + it.totalLinea);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE65100).withValues(alpha: 0.15),
                  child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold)),
                ),
                title: Text(
                  sale.alias,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  '${sale.items.length} artículos | Pausado: ${sale.heldAt.hour.toString().padLeft(2, '0')}:${sale.heldAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32)),
                ),
                onTap: () {
                  widget.cartController.resumeSale(idx);
                  Navigator.of(ctx).pop();
                  _refocusSearch();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar [ESC]'),
          ),
        ],
      ),
    ).then((_) => _refocusSearch());
  }

  Future<void> _openAdvancedProductSearch({String initialQuery = ''}) async {
    final selectedProduct = await AdvancedProductSearchDialog.show(
      context: context,
      salesRepository: widget.cartController.salesRepository,
      initialQuery: initialQuery,
    );
    if (selectedProduct != null && mounted) {
      await _handleSelectedCatalogItem(selectedProduct);
    }
    _refocusSearch();
  }

  Future<void> _openCashMovement() async {
    if (!widget.shiftController.hasActiveShift) {
      final opened = await OpenShiftDialog.show(context, widget.shiftController);
      if (!opened) return;
    }
    if (mounted) {
      await CashMovementDialog.show(context, widget.shiftController);
      _refocusSearch();
    }
  }

  Future<void> _openSalesHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalesHistoryScreen(
          authController: widget.authController,
          printerService: widget.printerService,
          activeShiftId: widget.shiftController.activeShiftId,
        ),
      ),
    );
    _refocusSearch();
  }

  Future<void> _openClientsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientsScreen(
          shiftController: widget.shiftController,
        ),
      ),
    );
    _refocusSearch();
  }

  Future<void> _openSettingsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(printerService: widget.printerService),
      ),
    );
    _refocusSearch();
  }

  Future<void> _showPriceTierMenu(SaleDetailItem item) async {
    if (item.productoId == 'ART-COMUN') return;

    final prod = await widget.cartController.salesRepository.findProductById(item.productoId) ??
        await widget.cartController.salesRepository.findProductByBarcodeOrSku(item.sku ?? item.productoId);
    if (!mounted) return;

    final baseProd = prod ?? Product(
      id: item.productoId,
      nombre: item.nombre,
      descripcion: item.descripcion,
      precioCompra: item.costoHistorico,
      precioVenta: item.precioHistorico,
      stockActual: item.stockDisponible,
    );

    final selected = await showModalBottomSheet<String>(
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
                      'Seleccionar Nivel de Precio para:\n${item.nombre}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
              const SizedBox(height: 12),
              ListTile(
                dense: true,
                leading: const Icon(Icons.people, color: Color(0xFF2E7D32)),
                title: const Text('Precio 1: Público Casual'),
                trailing: Text('\$${baseProd.precioVenta.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                selected: item.etiquetaPrecio == 'Público',
                onTap: () => Navigator.pop(ctx, 'Público'),
              ),
              if (baseProd.precioCerrajero != null && baseProd.precioCerrajero! > 0)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.vpn_key, color: Color(0xFF0D47A1)),
                  title: const Text('Precio 2: Colega Cerrajero / Gremio'),
                  trailing: Text('\$${baseProd.precioCerrajero!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  selected: item.etiquetaPrecio == 'Cerrajero',
                  onTap: () => Navigator.pop(ctx, 'Cerrajero'),
                ),
              if (baseProd.precioTaller != null && baseProd.precioTaller! > 0)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.build, color: Color(0xFF4A148C)),
                  title: const Text('Precio 3: Taller Automotriz / Especial'),
                  trailing: Text('\$${baseProd.precioTaller!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  selected: item.etiquetaPrecio == 'Taller',
                  onTap: () => Navigator.pop(ctx, 'Taller'),
                ),
              if (baseProd.precioMayoreo != null && baseProd.precioMayoreo! > 0)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory, color: Color(0xFFE65100)),
                  title: Text('Precio 4: Mayoreo (volumen >= ${baseProd.cantidadMayoreo ?? 5})'),
                  trailing: Text('\$${baseProd.precioMayoreo!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  selected: item.etiquetaPrecio == 'Mayoreo',
                  onTap: () => Navigator.pop(ctx, 'Mayoreo'),
                ),
              const Divider(height: 12),
              if (item.esServicio) ...[
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.tune, color: Color(0xFF00838F)),
                  title: const Text('Modificar precio e insumo ocupado...'),
                  subtitle: const Text('Editar precio unitario, cantidad de servicios e insumos consumidos'),
                  onTap: () => Navigator.pop(ctx, 'EditService'),
                ),
                const Divider(height: 12),
              ],
              ListTile(
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
    );

    if (selected == 'EditService' && mounted) {
      await EditServiceLineDialog.show(
        context: context,
        item: item,
        cartController: widget.cartController,
      );
      _refocusSearch();
      return;
    }

    if (selected == 'Manual' && mounted) {
      final manualCtrl = TextEditingController(text: item.precioHistorico.toStringAsFixed(2));
      manualCtrl.selection = TextSelection(baseOffset: 0, extentOffset: manualCtrl.text.length);
      final manualPrice = await showDialog<double>(
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
              child: TextField(
              controller: manualCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Precio unitario',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(dCtx, double.tryParse(v)),
            ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dCtx, double.tryParse(manualCtrl.text)),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );
      if (manualPrice != null && manualPrice >= 0) {
        widget.cartController.changeItemPriceTier(item.id, manualPrice, 'Manual');
      }
      _refocusSearch();
      return;
    }

    if (selected != null) {
      double chosenPrice = baseProd.precioVenta;
      if (selected == 'Cerrajero' && baseProd.precioCerrajero != null) {
        chosenPrice = baseProd.precioCerrajero!;
      } else if (selected == 'Taller' && baseProd.precioTaller != null) {
        chosenPrice = baseProd.precioTaller!;
      } else if (selected == 'Mayoreo' && baseProd.precioMayoreo != null) {
        chosenPrice = baseProd.precioMayoreo!;
      }

      widget.cartController.changeItemPriceTier(item.id, chosenPrice, selected);
    }
    _refocusSearch();
  }

  void _handleLogout() {
    widget.authController.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authController: widget.authController,
          posAppTarget: widget, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): AdvancedSearchIntent(),
        SingleActivator(LogicalKeyboardKey.f2): CommonArticleIntent(),
        SingleActivator(LogicalKeyboardKey.f3): OpenInventoryIntent(),
        SingleActivator(LogicalKeyboardKey.f4): ShiftCutIntent(),
        SingleActivator(LogicalKeyboardKey.f6): HoldSaleIntent(),
        SingleActivator(LogicalKeyboardKey.f7): ViewHeldSalesIntent(),
        SingleActivator(LogicalKeyboardKey.f8): QuoteIntent(),
        SingleActivator(LogicalKeyboardKey.f9): CashMovementIntent(),
        SingleActivator(LogicalKeyboardKey.f10): SalesHistoryIntent(),
        SingleActivator(LogicalKeyboardKey.f12): CheckoutIntent(),
        SingleActivator(LogicalKeyboardKey.delete, alt: true): ClearCartIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          AdvancedSearchIntent: CallbackAction<AdvancedSearchIntent>(onInvoke: (_) {
            _openAdvancedProductSearch();
            return null;
          }),
          CommonArticleIntent: CallbackAction<CommonArticleIntent>(onInvoke: (_) {
            CommonArticleDialog.show(context, widget.cartController).then((_) => _refocusSearch());
            return null;
          }),
          OpenInventoryIntent: CallbackAction<OpenInventoryIntent>(onInvoke: (_) {
            _openInventoryView();
            return null;
          }),
          ShiftCutIntent: CallbackAction<ShiftCutIntent>(onInvoke: (_) {
            _openShiftCutModal();
            return null;
          }),
          HoldSaleIntent: CallbackAction<HoldSaleIntent>(onInvoke: (_) {
            _handleHoldSaleWithAlias();
            return null;
          }),
          ViewHeldSalesIntent: CallbackAction<ViewHeldSalesIntent>(onInvoke: (_) {
            _showHeldSalesModal();
            return null;
          }),
          QuoteIntent: CallbackAction<QuoteIntent>(onInvoke: (_) {
            _openQuoteDialog();
            return null;
          }),
          CashMovementIntent: CallbackAction<CashMovementIntent>(onInvoke: (_) {
            _openCashMovement();
            return null;
          }),
          SalesHistoryIntent: CallbackAction<SalesHistoryIntent>(onInvoke: (_) {
            _openSalesHistory();
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
          onKeyEvent: (node, event) {
            // Manejo de teclas '+' y '-' para modificar ágilmente el último ítem
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.numpadAdd ||
                  (event.character == '+' && _searchController.text.isEmpty)) {
                _tryIncrementLastItem();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.numpadSubtract ||
                  (event.character == '-' && _searchController.text.isEmpty)) {
                widget.cartController.decrementLastItem();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFECEFF1),
            body: SafeArea(
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
          // Asignación de Cliente
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1F4E79),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: const BorderSide(color: Color(0xFFCFD8DC)),
            ),
            icon: const Icon(Icons.person_outline, size: 20),
            label: AnimatedBuilder(
              animation: widget.cartController,
              builder: (context, _) => Text(
                widget.cartController.selectedClientName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            onPressed: () async {
              final selectedClient = await ClientSelectionDialog.show(context);
              if (selectedClient != null && mounted) {
                widget.cartController.setClient(selectedClient.id, selectedClient.nombre);
              }
              _refocusSearch();
            },
          ),
          const SizedBox(width: 12),

          // Campo de búsqueda inteligente (Soporta comodín %)
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.go,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Clave/SKU, Barra, Nombre o con % (ej. %jetta, %phillips)... [F1]',
                prefixIcon: Icon(Icons.search, color: Color(0xFF1F4E79)),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9FAFB),
              ),
              onSubmitted: _handleBarcodeScan,
            ),
          ),
          const SizedBox(width: 8),

          // Iconos de acción con scroll horizontal para pantallas táctiles estrechas
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
                  ),

          // Clientes y Créditos
          IconButton(
            icon: const Icon(Icons.people_alt_outlined, color: Color(0xFF1F4E79)),
            tooltip: 'Clientes y Créditos',
            onPressed: _openClientsScreen,
          ),

          // Historial de Ventas [F10]
          IconButton(
            icon: const Icon(Icons.history_outlined, color: Color(0xFF1F4E79)),
            tooltip: 'Historial y Devoluciones [F10]',
            onPressed: _openSalesHistory,
          ),

          // Movimiento de Caja [F9]
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Color(0xFF1F4E79)),
            tooltip: 'Entrada / Salida de Efectivo [F9]',
            onPressed: _openCashMovement,
          ),

          // Acceso a Inventario Offline (F3)
          if (widget.authController.isAdmin)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF1F4E79)),
              tooltip: 'Inventario Dinámico [F3]',
              onPressed: _openInventoryView,
            ),

          // Corte de Caja (F4)
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: Color(0xFF1F4E79)),
            tooltip: 'Corte de Caja [F4]',
            onPressed: _openShiftCutModal,
          ),

          // Configuración del Sistema
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF1F4E79)),
            tooltip: 'Configuración del Negocio',
            onPressed: _openSettingsScreen,
          ),
          const SizedBox(width: 4),

          // Alertas de Escasez BI
          StockAlertsButton(alertsController: widget.alertsController),
          const SizedBox(width: 8),

          // Indicador de Sincronización Outbox
          SyncStatusBadge(syncWorker: widget.syncWorker),
          const SizedBox(width: 8),

          // Botón de Bloqueo / Logout
          Container(
            height: 36,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Colors.black12)),
            ),
            padding: const EdgeInsets.only(left: 8.0),
            child: IconButton(
              icon: const Icon(Icons.lock_outline, color: Color(0xFFD32F2F)),
              tooltip: 'Bloquear Terminal / Cerrar Sesión',
              onPressed: _handleLogout,
            ),
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA VISOR DEL TICKET ACTIVO (CONTROL RÁPIDO DE CANTIDADES Y UBICACIÓN)
  // ---------------------------------------------------------------------------
  Widget _buildActiveTicketTable() {
    return AnimatedBuilder(
      animation: widget.cartController,
      builder: (context, _) {
        final items = widget.cartController.items;

        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined, size: 64, color: Color(0xFF9E9E9E)),
                SizedBox(height: 12),
                Text(
                  'El ticket está vacío\nEscanea o busca por clave de llave, transponder o servicio.',
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
              // Encabezado de la Tabla
              Container(
                color: const Color(0xFF1F4E79),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                child: Row(
                  children: [
                    const SizedBox(width: 130, child: Text('CANT.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const Expanded(child: Text('PRODUCTO / SERVICIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    SizedBox(
                      width: 130,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PopupMenuButton<String>(
                          tooltip: 'Cambiar nivel de precio a todo el ticket',
                          padding: EdgeInsets.zero,
                          onSelected: (tier) {
                            widget.cartController.applyGlobalPriceTier(tier);
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'Público',
                              child: Row(
                                children: [
                                  Icon(Icons.people, size: 16, color: Color(0xFF2E7D32)),
                                  SizedBox(width: 8),
                                  Text('Público (Normal)'),
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
                    ),
                    const SizedBox(width: 100, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 40),
                  ],
                ),
              ),

              // Filas de Partidas
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isGranel = (item.cantidad % 1 != 0);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Control Rápido de Cantidad: [-] [ 1.0 ] [+]
                          SizedBox(
                            width: 130,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => widget.cartController.decrementQuantity(item.id),
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
                          ),
                          const SizedBox(width: 8),

                          // Descripción + Subtítulos Operativos (Ubicación y Costo)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.nombre,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (item.marca != null && item.marca!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        margin: const EdgeInsets.only(left: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCFD8DC),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          item.marca!,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF263238)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 2,
                                  children: [
                                    // UBICACIÓN FÍSICA (EXCLUSIVA DE PANTALLA)
                                    if (item.ubicacion != null && item.ubicacion!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3E0),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: const Color(0xFFFFB74D)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text('📍 ', style: TextStyle(fontSize: 9)),
                                            Text(
                                              item.ubicacion!,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                                            ),
                                          ],
                                        ),
                                      ),

                                    if (item.sku != null && item.sku!.isNotEmpty)
                                      Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 11, color: Colors.black54)),

                                    // BADGE DE DISPONIBILIDAD Y DESCUENTO DINÁMICO DE INSUMO (Nunca mostrar costo interno aquí)
                                    if (item.esServicio) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0F7FA),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: const Color(0xFF80DEEA)),
                                        ),
                                        child: const Text(
                                          '🛠️ Servicio',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF006064), fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (item.hasDynamicInsumo)
                                        InkWell(
                                          borderRadius: BorderRadius.circular(4),
                                          onTap: () {
                                            EditServiceLineDialog.show(
                                              context: context,
                                              item: item,
                                              cartController: widget.cartController,
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item.stockDisponible <= 0
                                                  ? Colors.red.shade50
                                                  : const Color(0xFFE8F5E9),
                                              borderRadius: BorderRadius.circular(3),
                                              border: Border.all(
                                                color: item.stockDisponible <= 0
                                                    ? Colors.red.shade300
                                                    : const Color(0xFF81C784),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.edit, size: 10, color: Color(0xFF1B5E20)),
                                                const SizedBox(width: 3),
                                                Text(
                                                  '🔧 ✏️ Insumo ocupado: ${(item.cantidadInsumoConsumida % 1 == 0 ? item.cantidadInsumoConsumida.toInt() : item.cantidadInsumoConsumida)} pza${(item.insumoUtilizadoNombre != null && item.insumoUtilizadoNombre!.isNotEmpty) ? " (${item.insumoUtilizadoNombre})" : ""} [Cambiar]',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: item.stockDisponible <= 0
                                                        ? Colors.red.shade800
                                                        : const Color(0xFF1B5E20),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ] else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: item.stockDisponible <= 0
                                              ? Colors.red.shade50
                                              : (item.stockDisponible <= 5 ? Colors.orange.shade50 : Colors.green.shade50),
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                            color: item.stockDisponible <= 0
                                                ? Colors.red.shade300
                                                : (item.stockDisponible <= 5 ? Colors.orange.shade300 : Colors.green.shade300),
                                          ),
                                        ),
                                        child: Text(
                                          item.stockDisponible <= 0
                                              ? 'Agotado (0)'
                                              : 'Stock: ${item.stockDisponible.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: item.stockDisponible <= 0
                                                ? Colors.red.shade800
                                                : (item.stockDisponible <= 5 ? Colors.orange.shade900 : Colors.green.shade800),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Precio Unitario Interactivo con Selector de Nivel
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
                          ),

                          // Total Línea
                          SizedBox(
                            width: 100,
                            child: Text(
                              '\$${item.totalLinea.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),

                          // Botón Eliminar Fila (Touch target >= 44x44)
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

  // ---------------------------------------------------------------------------
  // PANEL DE LIQUIDACIÓN Y BOTÓN DE COTIZACIÓN [F8]
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
              const SizedBox(height: 20),

              // Botón de Cotización / Ticket Digital [F8]
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
              const SizedBox(height: 12),

              // Totalizador Grande
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F4E79),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL A COBRAR', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Botón Principal de Cobro [F12]
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
    return AnimatedBuilder(
      animation: widget.cartController,
      builder: (context, _) {
        final heldCount = widget.cartController.heldSales.length;
        final hasHeld = heldCount > 0;

        return Container(
          color: const Color(0xFF263238),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _buildKeyBadge('F1', 'Buscar', _openAdvancedProductSearch),
              _buildKeyBadge('F2', 'Art. Común', () {
                CommonArticleDialog.show(context, widget.cartController).then((_) => _refocusSearch());
              }),
              if (widget.authController.isAdmin)
                _buildKeyBadge('F3', 'Inventario', _openInventoryView),
              _buildKeyBadge('F4', 'Corte Caja', _openShiftCutModal),
              _buildKeyBadge('F6', 'Pausar', _handleHoldSaleWithAlias),
              _buildKeyBadge(
                'F7',
                'Pausados ($heldCount)',
                _showHeldSalesModal,
                backgroundColor: hasHeld ? const Color(0xFFE65100) : null,
                borderColor: hasHeld ? const Color(0xFFFFB74D) : null,
              ),
              _buildKeyBadge('F8', 'Cotizar Digital', _openQuoteDialog),
              _buildKeyBadge('F9', 'E/S Dinero', _openCashMovement),
              _buildKeyBadge('F10', 'Historial Tickets', _openSalesHistory),
              _buildKeyBadge('+ / -', 'Cant. Rápida', () {}),
              _buildKeyBadge('Alt+Supr', 'Limpiar', () {
                widget.cartController.clearCart();
                _refocusSearch();
              }),
              _buildKeyBadge('F12', 'Cobrar', _triggerCheckout, backgroundColor: const Color(0xFF2E7D32)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKeyBadge(
    String keyLabel,
    String actionLabel,
    VoidCallback onTap, {
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0xFF37474F),
          borderRadius: BorderRadius.circular(3),
          border: borderColor != null ? Border.all(color: borderColor, width: 1.2) : null,
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