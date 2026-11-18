import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/string_utils.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/local/business_config.dart';
import '../../data/local/models.dart';
import '../../data/repositories/shift_repository.dart';
import '../controllers/shift_controller.dart';
import 'open_shift_dialog.dart';

/// Modal definitivo de Gestión de Cortes de Caja (Corte X y Corte Z).
/// Construido con layout rígido acotado (Dialog con SizedBox fija) para evitar
/// excepciones de RenderFlex / unbounded height en Windows Desktop.
class ShiftCutDialog extends StatefulWidget {
  final ShiftController shiftController;
  final PrinterService? printerService;

  const ShiftCutDialog({
    super.key,
    required this.shiftController,
    this.printerService,
  });

  static Future<void> show(
    BuildContext context,
    ShiftController controller, {
    PrinterService? printerService,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShiftCutDialog(
        shiftController: controller,
        printerService: printerService,
      ),
    );
  }

  @override
  State<ShiftCutDialog> createState() => _ShiftCutDialogState();
}

class _ShiftCutDialogState extends State<ShiftCutDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _cashCountedController = TextEditingController();
  final FocusNode _cashFocusNode = FocusNode();

  bool _isProcessing = false;
  bool _isLoadingSummary = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cashCountedController.addListener(() {
      if (mounted) setState(() {});
    });
    _initData();
  }

  Future<void> _initData() async {
    setState(() {
      _isLoadingSummary = true;
      _errorMessage = null;
    });

    try {
      await widget.shiftController.loadShiftSummary();
    } catch (e) {
      debugPrint('[SHIFT_CUT_DIALOG] Error al cargar resumen de caja: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSummary = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cashCountedController.dispose();
    _cashFocusNode.dispose();
    super.dispose();
  }

  double get _countedCash => double.tryParse(_cashCountedController.text.trim()) ?? 0.0;

  Future<void> _handlePrintCorteX() async {
    final summary = widget.shiftController.currentSummary;
    if (summary == null) return;

    if (widget.printerService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Servicio de impresión no vinculado.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final cfg = BusinessConfig.current;
    final now = DateTime.now();

    final ticketData = TicketPrintData(
      negocioNombre: cfg.negocioNombre.isNotEmpty ? cfg.negocioNombre : 'CARprog',
      negocioLeyenda: cfg.negocioLeyenda,
      rfc: cfg.negocioRfc,
      direccion: cfg.negocioDireccion,
      telefono: cfg.negocioTelefono,
      mensajeSuperior: '*** ARQUEO DE CAJA EN VIVO (CORTE X) ***',
      folio: 'CORTE-X-${now.millisecondsSinceEpoch.toString().safeSub(6)}',
      fecha: now,
      cajero: widget.shiftController.currentShift?.usuarioId ?? 'Caja 1',
      turnoId: summary.shiftId,
      clienteNombre: 'AUDITORÍA INTERNA DE CAJA',
      items: [
        SaleDetailItem(
          id: 'item-cx-efec',
          productoId: 'CX-EFEC',
          sku: '000000',
          nombre: 'VENTAS EN EFECTIVO',
          descripcion: 'Total efectivo cobrado',
          cantidad: 1,
          precioHistorico: summary.ventasEfectivo,
          costoHistorico: 0.0,
          totalLinea: summary.ventasEfectivo,
        ),
        SaleDetailItem(
          id: 'item-cx-tarj',
          productoId: 'CX-TARJ',
          sku: '000000',
          nombre: 'VENTAS EN TARJETA',
          descripcion: 'Débito / Crédito bancario',
          cantidad: 1,
          precioHistorico: summary.ventasTarjeta,
          costoHistorico: 0.0,
          totalLinea: summary.ventasTarjeta,
        ),
        SaleDetailItem(
          id: 'item-cx-tran',
          productoId: 'CX-TRAN',
          sku: '000000',
          nombre: 'VENTAS EN TRANSFERENCIA',
          descripcion: 'SPEI / Bancario',
          cantidad: 1,
          precioHistorico: summary.ventasTransferencia,
          costoHistorico: 0.0,
          totalLinea: summary.ventasTransferencia,
        ),
      ],
      subtotal: summary.totalVentas,
      total: summary.totalVentas,
      pagos: [
        PaymentMethodBreakdown(metodo: 'Efectivo en Cajón', monto: summary.totalEfectivoEsperado),
      ],
      cambio: 0.0,
      piePagina: 'Reporte interno para control de valores en caja.',
      garantia: 'Fondo Inicial: \$${summary.montoInicial.toStringAsFixed(2)} | Entradas: \$${summary.entradasEfectivo.toStringAsFixed(2)} | Retiros: \$${summary.salidasEfectivo.toStringAsFixed(2)}',
      mostrarCodigoBarras: false,
    );

    final res = await widget.printerService!.printSaleTicketAsync(ticketData);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.success ? const Color(0xFF2E7D32) : Colors.orange.shade800,
        ),
      );
    }
  }

  Future<void> _handleCloseShiftZ() async {
    final summary = widget.shiftController.currentSummary;
    if (summary == null || _isProcessing) return;

    final discrepancy = _countedCash - summary.totalEfectivoEsperado;
    final discrepancyText = discrepancy == 0
        ? 'Sin diferencia (Cuadre Exacto)'
        : (discrepancy > 0
            ? 'SOBRANTE: +\$${discrepancy.toStringAsFixed(2)}'
            : 'FALTANTE: -\$${discrepancy.abs().toStringAsFixed(2)}');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD32F2F)),
            SizedBox(width: 8),
            Text('Confirmación de Cierre Z', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          '¿Está seguro de cerrar el turno de caja de forma definitiva?\n\n'
          '• Efectivo esperado en cajón: \$${summary.totalEfectivoEsperado.toStringAsFixed(2)}\n'
          '• Efectivo contado físicamente: \$${_countedCash.toStringAsFixed(2)}\n'
          '• Resultado de Arqueo: $discrepancyText\n\n'
          'Esta operación sella el turno e inserta el evento de sincronización contable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar y Cerrar Turno'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      await widget.shiftController.closeShiftCorteZ(_countedCash);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turno cerrado exitosamente (Corte Z generado).'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screenSize.width * 0.95, 760.0);
    final dialogHeight = math.min(screenSize.height * 0.92, 640.0);

    final summary = widget.shiftController.currentSummary;
    final activeShift = widget.shiftController.currentShift;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isProcessing) Navigator.of(context).pop();
        },
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Azul Marino
              Container(
                color: const Color(0xFF1F4E79),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.point_of_sale, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gestión de Cortes de Caja',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            activeShift != null
                                ? 'Turno Activo ID: ${activeShift.id.safePrefix(8)} | Cajero: ${activeShift.usuarioId}'
                                : 'Modo Auditoría / Consolidado del Día',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 22),
                      tooltip: 'Cerrar (Esc)',
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // 2. Banner de Error si existe
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFFFFEBEE),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Color(0xFFC62828)),
                        onPressed: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ),

              // 3. Contenido Principal según Estado
              Expanded(
                child: _isLoadingSummary
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text(
                              'Calculando arqueo y métricas de corte...',
                              style: TextStyle(color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : summary == null
                        ? _buildEmptyState()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Banner si es consolidado global
                              if (summary.isConsolidatedDay)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  color: const Color(0xFFE3F2FD),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.admin_panel_settings, color: Color(0xFF1565C0), size: 18),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Vista Administrador: Consolidado Global de Hoy (No hay turno individual abierto)',
                                          style: TextStyle(
                                            color: Color(0xFF0D47A1),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1565C0),
                                          foregroundColor: Colors.white,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('Abrir Turno', style: TextStyle(fontSize: 11)),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          OpenShiftDialog.show(context, widget.shiftController);
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                              // TabBar de Cortes
                              Material(
                                color: Colors.grey.shade100,
                                child: TabBar(
                                  controller: _tabController,
                                  labelColor: const Color(0xFF1F4E79),
                                  unselectedLabelColor: Colors.grey.shade600,
                                  indicatorColor: const Color(0xFF1F4E79),
                                  indicatorWeight: 3,
                                  tabs: const [
                                    Tab(
                                      icon: Icon(Icons.info_outline, size: 18),
                                      text: 'Corte X (Arqueo Parcial en Vivo)',
                                    ),
                                    Tab(
                                      icon: Icon(Icons.lock_clock, size: 18),
                                      text: 'Corte Z (Cierre Definitivo de Turno)',
                                    ),
                                  ],
                                ),
                              ),

                              // Vistas de Pestañas
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _buildCorteXTab(summary),
                                    _buildCorteZTab(summary),
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 52, color: Colors.orange),
            const SizedBox(height: 12),
            const Text(
              'No hay turnos registrados el día de hoy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Para realizar cobros y llevar el control del efectivo en caja, debes iniciar un turno.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F4E79),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('➕ Abrir Nuevo Turno de Caja'),
              onPressed: () {
                Navigator.of(context).pop();
                OpenShiftDialog.show(context, widget.shiftController);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorteXTab(ShiftSummary summary) {
    final Map<String, double> deptos = summary.ventasPorDepartamento;

    return Scrollbar(
      thumbVisibility: true,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Dinero en Caja (Arqueo en Vivo)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.monetization_on_outlined, color: Color(0xFF1B5E20), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'DINERO EN CAJA (ARQUEO EN VIVO)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildMetricTile('  • Fondo Inicial de Caja:', '\$${summary.montoInicial.toStringAsFixed(2)}'),
                _buildMetricTile('  • (+) Ventas Cobradas en Efectivo:', '\$${summary.ventasEfectivo.toStringAsFixed(2)}'),
                _buildMetricTile('  • (+) Entradas Adicionales de Efectivo:', '\$${summary.entradasEfectivo.toStringAsFixed(2)}'),
                _buildMetricTile('  • (-) Salidas / Retiros / Gastos:', '\$${summary.salidasEfectivo.toStringAsFixed(2)}'),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'EFECTIVO ESPERADO EN CAJÓN:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B5E20)),
                    ),
                    Text(
                      '\$${summary.totalEfectivoEsperado.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B5E20)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Formas de Pago
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FORMAS DE PAGO RECIBIDAS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 8),
                _buildMetricTile('Efectivo:', '\$${summary.ventasEfectivo.toStringAsFixed(2)}'),
                _buildMetricTile('Tarjetas (Débito/Crédito):', '\$${summary.ventasTarjeta.toStringAsFixed(2)}'),
                _buildMetricTile('Transferencias SPEI:', '\$${summary.ventasTransferencia.toStringAsFixed(2)}'),
                const Divider(height: 10),
                _buildMetricTile('Total Ventas del Turno:', '\$${summary.totalVentas.toStringAsFixed(2)}', isBold: true),
                _buildMetricTile('Tickets Emitidos:', '${summary.totalTickets} comprobantes'),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Ventas por Departamento
          if (deptos.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VENTAS POR DEPARTAMENTO',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79)),
                  ),
                  const SizedBox(height: 8),
                  ...deptos.entries.map((e) => _buildMetricTile('${e.key}:', '\$${e.value.toStringAsFixed(2)}')),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // 4. Ganancia Estimada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFD1C4E9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GANANCIA ESTIMADA DEL TURNO:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4A148C)),
                ),
                Text(
                  '\$${summary.gananciaEstimada.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4A148C)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Botón de Impresión de Corte X
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('🖨️ IMPRIMIR TICKET DE CORTE X (ARQUEO)', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _handlePrintCorteX,
          ),
        ],
      ),
    );
  }

  Widget _buildCorteZTab(ShiftSummary summary) {
    if (summary.isConsolidatedDay) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_outlined, size: 48, color: Color(0xFF1F4E79)),
              const SizedBox(height: 12),
              const Text(
                'El Cierre Z Requiere un Turno de Cajero Activo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F4E79)),
              ),
              const SizedBox(height: 8),
              const Text(
                'El Cierre Z definitivo sella y liquida un turno individual de cajero. Actualmente estás visualizando el acumulado diario en modo Administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('➕ Abrir Turno de Cajero'),
                onPressed: () {
                  Navigator.of(context).pop();
                  OpenShiftDialog.show(context, widget.shiftController);
                },
              ),
            ],
          ),
        ),
      );
    }

    final discrepancy = _countedCash - summary.totalEfectivoEsperado;
    final hasCount = _cashCountedController.text.trim().isNotEmpty;

    Color badgeColor = Colors.grey;
    String badgeText = 'Pendiente de conteo';

    if (hasCount) {
      if (discrepancy == 0) {
        badgeColor = const Color(0xFF2E7D32);
        badgeText = 'CUADRE EXACTO (\$0.00)';
      } else if (discrepancy > 0) {
        badgeColor = const Color(0xFF0288D1);
        badgeText = 'SOBRANTE: +\$${discrepancy.toStringAsFixed(2)}';
      } else {
        badgeColor = const Color(0xFFD32F2F);
        badgeText = 'FALTANTE: -\$${discrepancy.abs().toStringAsFixed(2)}';
      }
    }

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF90CAF9)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Efectivo Teórico Esperado en Cajón:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1)),
                  ),
                  Text(
                    '\$${summary.totalEfectivoEsperado.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _cashCountedController,
              focusNode: _cashFocusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Efectivo Contado Físicamente (\$)',
                hintText: '0.00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                helperText: 'Ingrese el dinero físico total contado en billetes y monedas.',
              ),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resultado del Arqueo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(badgeText, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (!hasCount || _isProcessing) ? null : _handleCloseShiftZ,
              child: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      '🔒 EJECUTAR CORTE Z Y CERRAR TURNO DEFINITIVAMENTE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String val, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: TextStyle(fontSize: 13.5, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}
