import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/local/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Modelos y Repositorios Locales
import '../../core/string_utils.dart';
import '../../data/local/models.dart';
import '../../data/local/business_config.dart';
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
import '../widgets/unified_pricing_dialog.dart';

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
class ModuleVentasIntent extends Intent { const ModuleVentasIntent(); }
class ModuleClientesIntent extends Intent { const ModuleClientesIntent(); }
class ModuleProductosIntent extends Intent { const ModuleProductosIntent(); }
class ModuleInventarioIntent extends Intent { const ModuleInventarioIntent(); }
class ModuleHistorialIntent extends Intent { const ModuleHistorialIntent(); }

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
  int _activeModuleIndex = 0; // 0: Ventas (F1), 1: Clientes (F2), 2: Productos (F3), 3: Inventario (F4), 4: Historial (F10), 5: Configuración
  String _currentBusinessName = 'CARprog';
  String _currentBusinessSubtitle = 'Cerrajería y Electrónica';
  String? _currentLogoBase64;
  String _pdfSaveDirectory = r'C:\POS\Cotizaciones';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Búfer para capturar ráfagas de lector de código de barras USB/HID
  final StringBuffer _globalBarcodeBuffer = StringBuffer();
  DateTime _lastGlobalKeyTime = DateTime.now();

  bool _handleHardwareScanWedge(KeyEvent event) {
    if (_activeModuleIndex != 0) return false;
    if (_searchFocusNode.hasFocus) return false;

    if (event is KeyDownEvent) {
      final now = DateTime.now();
      final diff = now.difference(_lastGlobalKeyTime).inMilliseconds;
      _lastGlobalKeyTime = now;

      if (diff > 120) {
        _globalBarcodeBuffer.clear();
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_globalBarcodeBuffer.isNotEmpty) {
          final code = _globalBarcodeBuffer.toString().trim();
          _globalBarcodeBuffer.clear();
          if (code.length >= 3) {
            _handleBarcodeScan(code);
            return true;
          }
        }
      } else if (event.character != null &&
          event.character!.isNotEmpty &&
          event.character!.codeUnitAt(0) >= 32 &&
          event.character!.codeUnitAt(0) <= 126) {
        _globalBarcodeBuffer.write(event.character);
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareScanWedge);
    _loadBusinessBranding();
    widget.alertsController.loadAlerts(silent: true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _refocusSearch();
      await widget.shiftController.checkActiveShift();
      if (!widget.shiftController.hasActiveShift && mounted) {
        await OpenShiftDialog.show(context, widget.shiftController);
        if (mounted) _refocusSearch();
      }
    });
  }

  Future<void> _loadBusinessBranding() async {
    try {
      final config = await DatabaseHelper.instance.getAllConfig();
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _currentBusinessName = config['negocio_nombre'] ?? prefs.getString('negocio_nombre') ?? widget.nombreNegocio;
          _currentBusinessSubtitle = config['negocio_leyenda'] ?? prefs.getString('negocio_leyenda') ?? 'Cerrajería y Electrónica';
          _currentLogoBase64 = config['logo_base64'] ?? prefs.getString('logo_base64');
          _pdfSaveDirectory = config['ruta_guardado_pdf'] ?? prefs.getString('ruta_guardado_pdf') ?? r'C:\POS\Cotizaciones';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareScanWedge);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _switchModule(int index) {
    if (_activeModuleIndex == index) return;
    setState(() {
      _activeModuleIndex = index;
    });
    if (index == 0) {
      _refocusSearch();
    }
  }

  void _openSalesHistory() => _switchModule(4);

  /// Mantiene anclado el foco en la barra de búsqueda / escáner de forma 100% segura
  void _refocusSearch() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_activeModuleIndex != 0) return;
      final modalRoute = ModalRoute.of(context);
      if (modalRoute != null && !modalRoute.isCurrent) return;
      if (_searchFocusNode.canRequestFocus && !_searchFocusNode.hasFocus) {
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

    if (!mounted) return;

    if (results.length == 1) {
      await _handleSelectedCatalogItem(results.first);
    } else if (results.length > 1) {
      await _openAdvancedProductSearch(initialQuery: text);
    } else if (results.isEmpty) {
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

  void _openShiftCutModal() {
    ShiftCutDialog.show(context, widget.shiftController, printerService: widget.printerService);
  }

  void _openInventoryView() {
    _switchModule(3);
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
      nombreNegocio: _currentBusinessName,
      leyendaNegocio: _currentBusinessSubtitle,
      logoBase64: _currentLogoBase64,
      pdfSaveDirectory: _pdfSaveDirectory,
      clienteNombre: widget.cartController.selectedClientName,
      printerService: widget.printerService,
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
    final currentTotalBeforeCheckout = widget.cartController.total;
    final activeShiftId = widget.shiftController.activeShiftId;

    final checkoutResult = await showDialog<CheckoutResult>(
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

      final cfg = BusinessConfig.current;
      final double resolvedTotal = checkoutResult.totalFinal > 0
          ? checkoutResult.totalFinal
          : (currentTotalBeforeCheckout + checkoutResult.ajusteRedondeo);
      final ticketData = TicketPrintData(
        negocioNombre: cfg.negocioNombre.isNotEmpty ? cfg.negocioNombre : widget.nombreNegocio,
        negocioLeyenda: cfg.negocioLeyenda,
        rfc: cfg.negocioRfc,
        direccion: cfg.negocioDireccion,
        telefono: cfg.negocioTelefono,
        mensajeSuperior: cfg.ticketHeader,
        folio: folioTicket,
        fecha: DateTime.now(),
        cajero: widget.authController.currentUser?.nombre ?? widget.usuarioId,
        turnoId: activeShiftId,
        clienteNombre: widget.cartController.selectedClientName,
        items: currentItemsSnapshot,
        subtotal: currentSubtotal,
        descuentoTotal: currentDescuento,
        total: resolvedTotal,
        ajusteRedondeo: checkoutResult.ajusteRedondeo,
        pagos: checkoutResult.pagos.isNotEmpty
            ? checkoutResult.pagos
            : [
                PaymentMethodBreakdown(metodo: 'Liquidado', monto: resolvedTotal),
              ],
        cambio: checkoutResult.cambio,
        piePagina: cfg.ticketFooter,
        garantia: cfg.ticketGarantia,
        notasTicket: checkoutResult.notasTicket,
        fontFamily: cfg.ticketFontFamily,
        mostrarLogo: cfg.ticketMostrarLogo,
        mostrarNombre: cfg.ticketMostrarNombre,
        mostrarContacto: cfg.ticketMostrarContacto,
        mostrarFolioFecha: cfg.ticketMostrarFolioFecha,
        mostrarCajero: cfg.ticketMostrarCajero,
        mostrarCliente: cfg.ticketMostrarCliente,
        mostrarDescuentosRedondeo: cfg.ticketMostrarDescuentosRedondeo,
        mostrarTotalLetra: cfg.ticketMostrarTotalLetra,
        mostrarCodigoBarras: cfg.ticketMostrarCodigoBarras,
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



  Future<void> _showPriceTierMenu(SaleDetailItem item) async {
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
  }

  void _handleLogout() {
    widget.authController.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authController: widget.authController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f1): ModuleVentasIntent(),
        SingleActivator(LogicalKeyboardKey.f2): ModuleClientesIntent(),
        SingleActivator(LogicalKeyboardKey.f3): ModuleProductosIntent(),
        SingleActivator(LogicalKeyboardKey.f4): ModuleInventarioIntent(),
        SingleActivator(LogicalKeyboardKey.f5): ModuleHistorialIntent(),
        SingleActivator(LogicalKeyboardKey.f6): HoldSaleIntent(),
        SingleActivator(LogicalKeyboardKey.f7): ViewHeldSalesIntent(),
        SingleActivator(LogicalKeyboardKey.f8): QuoteIntent(),
        SingleActivator(LogicalKeyboardKey.f9): CashMovementIntent(),
        SingleActivator(LogicalKeyboardKey.f10): CommonArticleIntent(),
        SingleActivator(LogicalKeyboardKey.f11): ShiftCutIntent(),
        SingleActivator(LogicalKeyboardKey.f12): CheckoutIntent(),
        SingleActivator(LogicalKeyboardKey.delete, alt: true): ClearCartIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ModuleVentasIntent: CallbackAction<ModuleVentasIntent>(onInvoke: (_) {
            if (_activeModuleIndex != 0) {
              _switchModule(0);
            } else {
              _openAdvancedProductSearch();
            }
            return null;
          }),
          ModuleClientesIntent: CallbackAction<ModuleClientesIntent>(onInvoke: (_) {
            _switchModule(1);
            return null;
          }),
          ModuleProductosIntent: CallbackAction<ModuleProductosIntent>(onInvoke: (_) {
            _switchModule(2);
            return null;
          }),
          ModuleInventarioIntent: CallbackAction<ModuleInventarioIntent>(onInvoke: (_) {
            _openInventoryView();
            return null;
          }),
          ModuleHistorialIntent: CallbackAction<ModuleHistorialIntent>(onInvoke: (_) {
            _openSalesHistory();
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
          CommonArticleIntent: CallbackAction<CommonArticleIntent>(onInvoke: (_) {
            CommonArticleDialog.show(context, widget.cartController).then((_) => _refocusSearch());
            return null;
          }),
          CheckoutIntent: CallbackAction<CheckoutIntent>(onInvoke: (_) {
            if (_activeModuleIndex != 0) _switchModule(0);
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
            if (_activeModuleIndex != 0) return KeyEventResult.ignored;
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
                      // Barra Superior de Módulos (App Shell estilo Eleventa Modernizado)
                      _buildTopAppShellBar(),
                      Expanded(
                        child: IndexedStack(
                          index: _activeModuleIndex,
                          children: [
                            // 0: Ventas (F1)
                            _buildVentasWorkspace(isWide, constraints),
                            // 1: Clientes (F2)
                            ClientsScreen(
                              shiftController: widget.shiftController,
                              showAppBar: false,
                            ),
                            // 2: Productos (F3)
                            InventoryScreen(
                              apiClient: widget.inventoryApiClient,
                              authController: widget.authController,
                              initialTabIndex: 0,
                              showAppBar: false,
                            ),
                            // 3: Inventario (F4)
                            InventoryScreen(
                              apiClient: widget.inventoryApiClient,
                              authController: widget.authController,
                              initialTabIndex: 1,
                              showAppBar: false,
                            ),
                            // 4: Historial / Facturas
                            SalesHistoryScreen(
                              authController: widget.authController,
                              printerService: widget.printerService,
                              activeShiftId: widget.shiftController.activeShiftId,
                              showAppBar: false,
                            ),
                            // 5: Configuración
                            SettingsScreen(
                              printerService: widget.printerService,
                              cartController: widget.cartController,
                              showAppBar: false,
                              onSettingsSaved: _loadBusinessBranding,
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildVentasWorkspace(bool isWide, BoxConstraints constraints) {
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
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BARRA SUPERIOR DE MÓDULOS PRINCIPALES (APP SHELL ESTILO ELEVENTA)
  // ---------------------------------------------------------------------------
  Widget _buildTopAppShellBar() {
    return Container(
      height: 52,
      color: const Color(0xFF1F4E79),
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          // Logo + Nombre y Leyenda del Negocio (a la izquierda, compacto)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentLogoBase64 != null && _currentLogoBase64!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    base64Decode(_currentLogoBase64!),
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.point_of_sale, color: Color(0xFFFFB74D), size: 22),
                  ),
                )
              else
                const Icon(Icons.point_of_sale, color: Color(0xFFFFB74D), size: 22),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentBusinessName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _currentBusinessSubtitle,
                    style: const TextStyle(
                      color: Color(0xFFFFB74D),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 14),
          const VerticalDivider(color: Colors.white24, indent: 12, endIndent: 12),
          const SizedBox(width: 6),

          // Pestañas Principales (Ventas, Productos, Historial, Configuración, Corte)
          // Protegido con SingleChildScrollView para garantizar que JAMÁS se oculte Configuración
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModuleNavButton(
                    index: 0,
                    icon: Icons.shopping_cart_outlined,
                    label: 'F1 Ventas',
                  ),
                  const SizedBox(width: 4),
                  _buildModuleNavButton(
                    index: 2,
                    icon: Icons.sell_outlined,
                    label: 'F3 Productos',
                  ),
                  const SizedBox(width: 4),
                  _buildModuleNavButton(
                    index: 4,
                    icon: Icons.receipt_long_outlined,
                    label: 'Historial',
                  ),
                  const SizedBox(width: 4),
                  _buildModuleNavButton(
                    index: 5,
                    icon: Icons.settings_outlined,
                    label: 'Configuración',
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFB74D),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.monetization_on_outlined, size: 16),
                    label: const Text(
                      '🧮 Corte',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _openShiftCutModal,
                  ),
                ],
              ),
            ),
          ),

          // Indicadores del Extremo Derecho
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Usuario activo (👤 Sesión: Nombre sin redundancias)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 15, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      widget.authController.currentUser?.nombre ?? widget.usuarioId,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Alertas Predictivas
              StockAlertsButton(alertsController: widget.alertsController),
              const SizedBox(width: 8),

              // Sincronización Outbox
              SyncStatusBadge(syncWorker: widget.syncWorker),
              const SizedBox(width: 8),

              // Bloqueo / Salir
              IconButton(
                icon: const Icon(Icons.lock_outline, color: Color(0xFFFF8A80), size: 20),
                tooltip: 'Bloquear Terminal / Salir',
                onPressed: _handleLogout,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModuleNavButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _activeModuleIndex == index;
    return Material(
      color: isSelected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _switchModule(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? const Color(0xFF1F4E79) : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? const Color(0xFF1F4E79) : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BARRA DE VENTAS DESATURADA (F1 VENTAS)
  // ---------------------------------------------------------------------------
  Widget _buildHeaderBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          // 1. Botón Limpio de Cliente asignado al ticket actual (Público en General)
          AnimatedBuilder(
            animation: widget.cartController,
            builder: (context, _) {
              final isPublic = widget.cartController.selectedClientId == 'PUBLICO-GRAL';
              final tier = widget.cartController.selectedClientTier;
              final isSpecialTier = tier != 'Público';

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240, minWidth: 150),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPublic ? Colors.white : const Color(0xFFE8F5E9),
                    foregroundColor: const Color(0xFF1F4E79),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    side: BorderSide(
                      color: isPublic ? const Color(0xFFCFD8DC) : const Color(0xFF2E7D32),
                      width: isPublic ? 1.0 : 1.5,
                    ),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final selectedClient = await ClientSelectionDialog.show(
                      context,
                      onNavigateToClientsModule: () {
                        setState(() => _activeModuleIndex = 1);
                      },
                    );
                    if (!mounted) return;
                    if (selectedClient != null) {
                      widget.cartController.setClient(
                        selectedClient.id,
                        selectedClient.nombre,
                        tier: selectedClient.tarifaPreferencial,
                      );
                    }
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (mounted) _refocusSearch();
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPublic ? Icons.storefront : Icons.person,
                        size: 18,
                        color: isPublic ? const Color(0xFF1F4E79) : const Color(0xFF2E7D32),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.cartController.selectedClientName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isSpecialTier)
                              Text(
                                'Tarifa: $tier',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF0D47A1), fontWeight: FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.blueGrey),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // 2. Barra de Búsqueda / Escáner amplia y cómoda
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.go,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Clave/SKU, Barra, Nombre o con % (ej. %jetta, %phillips)... [F1]',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1F4E79)),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _refocusSearch();
                        },
                      )
                    : null,
              ),
              onSubmitted: _handleBarcodeScan,
            ),
          ),
          const SizedBox(width: 10),

          // 3. Botones rápidos exclusivos de la operación de caja
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Buscar [F1]
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F4E79),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  elevation: 0,
                ),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar [F1]', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _openAdvancedProductSearch,
              ),
              const SizedBox(width: 8),

              // Art. Común
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F4E79),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  side: const BorderSide(color: Color(0xFFCFD8DC)),
                ),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('[F10] Art. Común', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  CommonArticleDialog.show(context, widget.cartController).then((_) => _refocusSearch());
                },
              ),
              const SizedBox(width: 8),

              // Entradas / Salidas
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F4E79),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  side: const BorderSide(color: Color(0xFFCFD8DC)),
                ),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('[F9] Entradas/Salidas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _openCashMovement,
              ),
              const SizedBox(width: 8),

              // Pausar [F6]
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE65100),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  side: const BorderSide(color: Color(0xFFFFCC80)),
                ),
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: const Text('Pausar [F6]', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _handleHoldSaleWithAlias,
              ),
              const SizedBox(width: 8),

              // Pausados (N) [F7]
              AnimatedBuilder(
                animation: widget.cartController,
                builder: (context, _) {
                  final count = widget.cartController.heldSalesCount;
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: count > 0 ? const Color(0xFFE65100) : Colors.grey.shade200,
                      foregroundColor: count > 0 ? Colors.white : Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      elevation: count > 0 ? 1 : 0,
                    ),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text('Pausados ($count) [F7]', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: _showHeldSalesModal,
                  );
                },
              ),
            ],
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
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFFF8A80), size: 18),
                        tooltip: 'Limpiar ticket completo [Alt+Supr]',
                        onPressed: () {
                          if (widget.cartController.isNotEmpty) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('¿Limpiar ticket?'),
                                content: const Text('Se eliminarán todos los artículos del ticket actual.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    onPressed: () {
                                      widget.cartController.clear();
                                      Navigator.pop(ctx);
                                      _refocusSearch();
                                    },
                                    child: const Text('Limpiar'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Barra de Utilidades Rápidas de la Tabla (Mayoreo Auto ON/OFF)
              Container(
                color: const Color(0xFFF1F5F9),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => widget.cartController.toggleMayoreoAuto(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.cartController.mayoreoAutoEnabled ? const Color(0xFFE8F5E9) : const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: widget.cartController.mayoreoAutoEnabled ? const Color(0xFFA5D6A7) : Colors.grey.shade400,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.cartController.mayoreoAutoEnabled ? Icons.bolt : Icons.flash_off,
                              size: 14,
                              color: widget.cartController.mayoreoAutoEnabled ? const Color(0xFF2E7D32) : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Mayoreo Auto: ${widget.cartController.mayoreoAutoEnabled ? 'ENCENDIDO' : 'APAGADO'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: widget.cartController.mayoreoAutoEnabled ? const Color(0xFF1B5E20) : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '${items.length} partida${items.length == 1 ? "" : "s"} en ticket | Alt+Supr para limpiar',
                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
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

                          // P. Unitario con Gestor Unificado PopOver
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
                        '\$${calcularRedondeoEfectivo(total).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Exacto: \$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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
  // BARRA INFERIOR NO REDUNDANTE DE ACCESOS RÁPIDAS
  // ---------------------------------------------------------------------------
  // ignore: unused_element
  Widget _buildNonRedundantBottomBar() {
    return Container(
      height: 38,
      color: const Color(0xFF263238),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildBottomActionItem(
              keyLabel: 'F2',
              actionLabel: 'Clientes',
              icon: Icons.people_outline,
              onTap: () => _switchModule(1),
            ),
            const SizedBox(width: 8),
            _buildBottomActionItem(
              keyLabel: 'F4',
              actionLabel: 'Inventario',
              icon: Icons.inventory_2_outlined,
              onTap: _openInventoryView,
            ),
            const SizedBox(width: 8),
            _buildBottomActionItem(
              keyLabel: 'F8',
              actionLabel: 'Cotizar',
              icon: Icons.request_quote_outlined,
              onTap: _openQuoteDialog,
            ),
            const SizedBox(width: 8),
            _buildBottomActionItem(
              keyLabel: 'Alt+Supr',
              actionLabel: 'Limpiar Ticket',
              icon: Icons.delete_sweep_outlined,
              onTap: () {
                if (widget.cartController.isNotEmpty) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('¿Limpiar ticket?'),
                      content: const Text('Se eliminarán todos los artículos del ticket actual.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () {
                            widget.cartController.clear();
                            Navigator.pop(ctx);
                            _refocusSearch();
                          },
                          child: const Text('Limpiar'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
            _buildBottomActionItem(
              keyLabel: 'F12',
              actionLabel: 'Cobrar',
              icon: Icons.check_circle_outline,
              backgroundColor: const Color(0xFF2E7D32),
              onTap: _triggerCheckout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionItem({
    required String keyLabel,
    required String actionLabel,
    required IconData icon,
    required VoidCallback onTap,
    Color? backgroundColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0xFF37474F),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                keyLabel,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              actionLabel,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
