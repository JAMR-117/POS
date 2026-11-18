import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/local/business_config.dart';
import '../../data/local/models.dart';
import '../../data/repositories/sales_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/admin_auth_dialog.dart';

enum DateFilterPeriod {
  today,
  yesterday,
  last7Days,
  thisMonth,
  custom,
  all,
}

enum AuditMovementType {
  venta,
  ventaCancelada,
  entradaCaja,
  salidaCaja,
  abonoCredito,
}

class AuditMovementItem {
  final String id;
  final DateTime fecha;
  final AuditMovementType tipo;
  final String titulo;
  final String concepto;
  final double monto;
  final String? usuario;
  final String? metodoPago;

  const AuditMovementItem({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.titulo,
    required this.concepto,
    required this.monto,
    this.usuario,
    this.metodoPago,
  });

  bool get esEntrada =>
      tipo == AuditMovementType.venta ||
      tipo == AuditMovementType.entradaCaja ||
      tipo == AuditMovementType.abonoCredito;
}

/// Centro de Auditoría Integral y Gestión Histórica del POS.
/// Incluye 4 Vistas:
/// 1. Timeline unificado de Todos los Movimientos
/// 2. Ventas y Tickets (Master-Detail con reimpresión, cancelación y devolución)
/// 3. Movimientos de Inventario (Entradas, salidas, mermas, ajustes)
/// 4. Flujo de Efectivo y Abonos de Crédito
class SalesHistoryScreen extends StatefulWidget {
  final AuthController authController;
  final PrinterService? printerService;
  final String? activeShiftId;
  final bool showAppBar;

  const SalesHistoryScreen({
    super.key,
    required this.authController,
    this.printerService,
    this.activeShiftId,
    this.showAppBar = true,
  });

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SalesRepository _salesRepo = SalesRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;

  // Filtros de Auditoría
  DateFilterPeriod _selectedPeriod = DateFilterPeriod.today;
  DateTimeRange? _customDateRange;
  String _selectedStatus = 'todos'; // 'todos' | 'completado' | 'cancelado'

  // Datos
  List<SaleRecord> _sales = [];
  List<Map<String, dynamic>> _inventoryMovements = [];
  List<Map<String, dynamic>> _cashMovements = [];
  List<Map<String, dynamic>> _creditPayments = [];
  List<AuditMovementItem> _timeline = [];

  // Master-Detail Inspector de Ventas
  SaleRecord? _selectedSale;
  List<SaleDetailItem> _selectedDetails = [];
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllAuditData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) _calculateDateBounds() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case DateFilterPeriod.today:
        final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return (start, end);
      case DateFilterPeriod.yesterday:
        final yest = now.subtract(const Duration(days: 1));
        final start = DateTime(yest.year, yest.month, yest.day, 0, 0, 0);
        final end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59, 999);
        return (start, end);
      case DateFilterPeriod.last7Days:
        final start = now.subtract(const Duration(days: 7));
        return (DateTime(start.year, start.month, start.day, 0, 0, 0), now);
      case DateFilterPeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1, 0, 0, 0);
        return (start, now);
      case DateFilterPeriod.custom:
        if (_customDateRange != null) {
          final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day, 0, 0, 0);
          final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59, 999);
          return (start, end);
        }
        return (null, null);
      case DateFilterPeriod.all:
        return (null, null);
    }
  }

  Future<void> _loadAllAuditData() async {
    setState(() => _isLoading = true);
    final (start, end) = _calculateDateBounds();
    final query = _searchController.text.trim();

    try {
      final sales = await _salesRepo.getSalesHistory(
        query: query,
        startDate: start,
        endDate: end,
        estatus: _selectedStatus,
        limit: 300,
      );

      final inv = await _salesRepo.getInventoryMovements(
        startDate: start,
        endDate: end,
        query: query,
        limit: 300,
      );

      final cash = await _salesRepo.getCashMovements(
        startDate: start,
        endDate: end,
        limit: 300,
      );

      final credit = await _salesRepo.getCreditPayments(
        startDate: start,
        endDate: end,
        limit: 300,
      );

      // Compilar Timeline unificado de auditoría
      final List<AuditMovementItem> items = [];

      for (final s in sales) {
        items.add(
          AuditMovementItem(
            id: s.id,
            fecha: s.fechaVentaLocal,
            tipo: s.isCancelado ? AuditMovementType.ventaCancelada : AuditMovementType.venta,
            titulo: 'Ticket: ${s.folioTicket}',
            concepto: s.isCancelado ? 'Venta Cancelada / Reversada' : 'Venta a ${s.clienteNombre}',
            monto: s.total,
            usuario: s.cajero,
            metodoPago: s.primaryPaymentMethod,
          ),
        );
      }

      for (final m in cash) {
        final tipoStr = (m['tipo'] as String? ?? 'entrada').toLowerCase();
        final isEntrada = tipoStr == 'entrada';
        final monto = (m['monto'] as num?)?.toDouble() ?? 0.0;
        final fechaStr = m['fecha'] as String? ?? DateTime.now().toIso8601String();
        final dt = DateTime.tryParse(fechaStr)?.toLocal() ?? DateTime.now();

        items.add(
          AuditMovementItem(
            id: m['id'] as String? ?? 'mov-${dt.millisecondsSinceEpoch}',
            fecha: dt,
            tipo: isEntrada ? AuditMovementType.entradaCaja : AuditMovementType.salidaCaja,
            titulo: isEntrada ? 'Entrada de Efectivo a Caja' : 'Retiro / Gasto de Caja',
            concepto: m['concepto'] as String? ?? 'Sin concepto',
            monto: monto,
            usuario: 'Caja',
            metodoPago: 'Efectivo',
          ),
        );
      }

      for (final ab in credit) {
        final monto = (ab['monto'] as num?)?.toDouble() ?? 0.0;
        final fechaStr = ab['fecha'] as String? ?? DateTime.now().toIso8601String();
        final dt = DateTime.tryParse(fechaStr)?.toLocal() ?? DateTime.now();
        final clienteNom = ab['cliente_nombre'] as String? ?? 'Cliente';

        items.add(
          AuditMovementItem(
            id: ab['id'] as String? ?? 'ab-${dt.millisecondsSinceEpoch}',
            fecha: dt,
            tipo: AuditMovementType.abonoCredito,
            titulo: 'Abono de Crédito Recibido',
            concepto: 'Cobro de saldo a $clienteNom',
            monto: monto,
            usuario: 'Caja',
            metodoPago: 'Efectivo',
          ),
        );
      }

      items.sort((a, b) => b.fecha.compareTo(a.fecha));

      if (!mounted) return;

      setState(() {
        _sales = sales;
        _inventoryMovements = inv;
        _cashMovements = cash;
        _creditPayments = credit;
        _timeline = items;

        if (_selectedSale != null) {
          final match = _sales.where((s) => s.id == _selectedSale!.id).toList();
          if (match.isNotEmpty) {
            _selectedSale = match.first;
          } else {
            _selectedSale = null;
            _selectedDetails = [];
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando auditoría: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectSale(SaleRecord sale) async {
    setState(() {
      _selectedSale = sale;
      _isLoadingDetails = true;
    });

    try {
      final details = await _salesRepo.getSaleDetails(sale.id);
      if (mounted && _selectedSale?.id == sale.id) {
        setState(() {
          _selectedDetails = details;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar partidas del ticket: $e')),
        );
      }
    }
  }

  Future<void> _reprintTicket(SaleRecord sale, List<SaleDetailItem> details) async {
    if (widget.printerService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servicio de impresión no configurado.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final cfg = BusinessConfig.current;
    final ticketData = TicketPrintData(
      negocioNombre: cfg.negocioNombre.isNotEmpty ? cfg.negocioNombre : 'CARprog',
      negocioLeyenda: cfg.negocioLeyenda,
      rfc: cfg.negocioRfc,
      direccion: cfg.negocioDireccion,
      telefono: cfg.negocioTelefono,
      mensajeSuperior: '*** REIMPRESIÓN DE COMPROBANTE ***',
      folio: '${sale.folioTicket} (COPIA)',
      fecha: sale.fechaVenta,
      cajero: sale.cajero.isNotEmpty ? sale.cajero : (widget.authController.currentUser?.nombre ?? 'Cajero'),
      turnoId: sale.corteCajaId.isNotEmpty ? sale.corteCajaId : 'HISTORIAL',
      clienteNombre: sale.clienteNombre,
      items: details,
      subtotal: sale.subtotal,
      descuentoTotal: sale.descuentoTotal,
      total: sale.total,
      ajusteRedondeo: sale.ajusteRedondeo,
      pagos: [PaymentMethodBreakdown(metodo: sale.primaryPaymentMethod, monto: sale.total)],
      cambio: 0.0,
      piePagina: cfg.ticketFooter,
      garantia: cfg.ticketGarantia,
      notasTicket: sale.notasTicket,
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

  Future<void> _cancelSale(SaleRecord sale, List<SaleDetailItem> details) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828)),
            const SizedBox(width: 8),
            Text('¿Cancelar Ticket ${sale.folioTicket}?'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Esta acción anulará la venta por un total de \$${sale.total.toStringAsFixed(2)} y reintegrará inmediatamente las siguientes partidas al inventario:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ...details.map((d) {
                final insumoNote = d.hasDynamicInsumo
                    ? ' (+ Reintegra ${d.cantidadInsumoConsumida.toStringAsFixed(d.cantidadInsumoConsumida % 1 == 0 ? 0 : 2)}x insumo ${d.insumoUtilizadoSku ?? d.insumoUtilizadoId})'
                    : '';
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
        _loadAllAuditData();
        if (_selectedSale?.id == sale.id) {
          _selectSale(sale);
        }
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
              width: 580,
              height: 440,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Selecciona las unidades a devolver para reintegrar automáticamente productos o insumos al inventario:',
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
                                          '🔑 Insumo vinculado: ${item.cantidadInsumoConsumida.toStringAsFixed(item.cantidadInsumoConsumida % 1 == 0 ? 0 : 2)}x ${item.insumoUtilizadoSku ?? item.insumoUtilizadoId}',
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
                                width: 85,
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
          _loadAllAuditData();
          if (_selectedSale?.id == sale.id) {
            _selectSale(sale);
          }
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

  void _exportAuditSummary() {
    final (start, end) = _calculateDateBounds();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final startStr = start != null ? fmt.format(start) : 'Inicio';
    final endStr = end != null ? fmt.format(end) : 'Presente';

    final completedSales = _sales.where((s) => !s.isCancelado).toList();
    final totalVendido = completedSales.fold(0.0, (acc, s) => acc + s.total);

    double totalEntradas = 0.0;
    double totalSalidas = 0.0;
    for (final m in _cashMovements) {
      final tipo = (m['tipo'] as String? ?? '').toLowerCase();
      final monto = (m['monto'] as num?)?.toDouble() ?? 0.0;
      if (tipo == 'entrada') {
        totalEntradas += monto;
      } else {
        totalSalidas += monto;
      }
    }

    double totalAbonos = 0.0;
    for (final ab in _creditPayments) {
      totalAbonos += (ab['monto'] as num?)?.toDouble() ?? 0.0;
    }

    final balanceNeto = totalVendido + totalEntradas + totalAbonos - totalSalidas;

    final summaryText = '''
========================================
AUDITORÍA INTEGRAL DE MOVIMIENTOS - POS
Período: $startStr al $endStr
========================================
• Ventas Netas Totales: \$${totalVendido.toStringAsFixed(2)} (${completedSales.length} tickets)
• Ventas Canceladas: ${_sales.where((s) => s.isCancelado).length} tickets
• Entradas de Caja: \$${totalEntradas.toStringAsFixed(2)}
• Abonos a Crédito: \$${totalAbonos.toStringAsFixed(2)}
• Salidas / Retiros / Gastos: -\$${totalSalidas.toStringAsFixed(2)}
----------------------------------------
BALANCE ESTIMADO EN CAJA: \$${balanceNeto.toStringAsFixed(2)}
========================================
Movimientos de Inventario Registrados: ${_inventoryMovements.length}
Total Eventos Cronológicos: ${_timeline.length}
''';

    Clipboard.setData(ClipboardData(text: summaryText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Resumen de auditoría copiado al portapapeles.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedSales = _sales.where((s) => !s.isCancelado).toList();
    final totalVendido = completedSales.fold(0.0, (acc, s) => acc + s.total);

    double totalEntradas = 0.0;
    double totalSalidas = 0.0;
    for (final m in _cashMovements) {
      final tipo = (m['tipo'] as String? ?? '').toLowerCase();
      final monto = (m['monto'] as num?)?.toDouble() ?? 0.0;
      if (tipo == 'entrada') {
        totalEntradas += monto;
      } else {
        totalSalidas += monto;
      }
    }

    double totalAbonos = 0.0;
    for (final ab in _creditPayments) {
      totalAbonos += (ab['monto'] as num?)?.toDouble() ?? 0.0;
    }

    final totalEntradasYAbonos = totalEntradas + totalAbonos;
    final balanceNetoEfectivo = totalVendido + totalEntradasYAbonos - totalSalidas;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Auditoría Integral y Movimientos de Caja/Inventario'),
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
              elevation: 2,
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy_all),
                  tooltip: 'Copiar Resumen de Auditoría',
                  onPressed: _exportAuditSummary,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refrescar Datos',
                  onPressed: _loadAllAuditData,
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          // 1. Selector de Períodos y Barra de Búsqueda
          _buildFilterBar(),

          // 2. Tarjetas de KPI del Período
          _buildKpiCards(
            totalVendido: totalVendido,
            totalEntradasAbonos: totalEntradasYAbonos,
            totalSalidasGastos: totalSalidas,
            balanceNetoEfectivo: balanceNetoEfectivo,
          ),

          // 3. TabBar de las 4 Vistas de Auditoría
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF1F4E79),
              unselectedLabelColor: Colors.black54,
              indicatorColor: const Color(0xFF1F4E79),
              indicatorWeight: 3,
              tabs: [
                Tab(
                  icon: const Icon(Icons.history_toggle_off, size: 18),
                  text: 'Todos los Movimientos (${_timeline.length})',
                ),
                Tab(
                  icon: const Icon(Icons.receipt_long, size: 18),
                  text: 'Ventas y Tickets (${_sales.length})',
                ),
                Tab(
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  text: 'Inventario (${_inventoryMovements.length})',
                ),
                Tab(
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  text: 'Flujo de Efectivo / Abonos (${_cashMovements.length + _creditPayments.length})',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFCFD8DC)),

          // 4. Contenido de Pestañas
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTimelineTab(),
                      _buildSalesTab(),
                      _buildInventoryTab(),
                      _buildCashFlowTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por Folio (TK-...), Cliente, Producto o Concepto...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF1F4E79), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadAllAuditData();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                  onSubmitted: (_) => _loadAllAuditData(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F4E79),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Buscar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _loadAllAuditData,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Exportar Resumen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _exportAuditSummary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPeriodChip(DateFilterPeriod.today, '📅 Hoy'),
                _buildPeriodChip(DateFilterPeriod.yesterday, 'Ayer'),
                _buildPeriodChip(DateFilterPeriod.last7Days, 'Últimos 7 días'),
                _buildPeriodChip(DateFilterPeriod.thisMonth, 'Este Mes'),
                _buildPeriodChip(
                  DateFilterPeriod.custom,
                  _customDateRange != null
                      ? '${DateFormat('dd/MM').format(_customDateRange!.start)} - ${DateFormat('dd/MM').format(_customDateRange!.end)}'
                      : 'Personalizado...',
                  isCustom: true,
                ),
                _buildPeriodChip(DateFilterPeriod.all, 'Todo el Historial'),
                const SizedBox(width: 16),
                Container(height: 20, width: 1, color: Colors.grey.shade300),
                const SizedBox(width: 16),
                _buildStatusChip('todos', 'Todos los Tickets'),
                _buildStatusChip('completado', 'Completados'),
                _buildStatusChip('cancelado', 'Cancelados'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(DateFilterPeriod period, String label, {bool isCustom = false}) {
    final isSelected = _selectedPeriod == period;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: const Color(0xFF1F4E79),
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF37474F),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: const Color(0xFFECEFF1),
        onSelected: (val) async {
          if (isCustom) {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: _customDateRange ??
                  DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 3)),
                    end: DateTime.now(),
                  ),
            );
            if (picked != null) {
              setState(() {
                _customDateRange = picked;
                _selectedPeriod = DateFilterPeriod.custom;
              });
              _loadAllAuditData();
            }
          } else {
            setState(() => _selectedPeriod = period);
            _loadAllAuditData();
          }
        },
      ),
    );
  }

  Widget _buildStatusChip(String status, String label) {
    final isSelected = _selectedStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: status == 'cancelado' ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF37474F),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        backgroundColor: const Color(0xFFECEFF1),
        onSelected: (val) {
          setState(() => _selectedStatus = status);
          _loadAllAuditData();
        },
      ),
    );
  }

  Widget _buildKpiCards({
    required double totalVendido,
    required double totalEntradasAbonos,
    required double totalSalidasGastos,
    required double balanceNetoEfectivo,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          _buildKpiCard('Ventas Netas Totales', '\$${totalVendido.toStringAsFixed(2)}', Icons.point_of_sale, const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          _buildKpiCard('Entradas / Abonos', '+\$${totalEntradasAbonos.toStringAsFixed(2)}', Icons.arrow_downward, const Color(0xFF00838F)),
          const SizedBox(width: 8),
          _buildKpiCard('Salidas / Gastos', '-\$${totalSalidasGastos.toStringAsFixed(2)}', Icons.arrow_upward, const Color(0xFFC62828)),
          const SizedBox(width: 8),
          _buildKpiCard(
            'Balance Neto en Caja',
            '\$${balanceNetoEfectivo.toStringAsFixed(2)}',
            Icons.account_balance_wallet,
            balanceNetoEfectivo >= 0 ? const Color(0xFF1F4E79) : const Color(0xFFD32F2F),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    val,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: TIMELINE DE TODOS LOS MOVIMIENTOS ---
  Widget _buildTimelineTab() {
    if (_timeline.isEmpty) {
      return const Center(child: Text('No hay movimientos registrados en el período seleccionado.'));
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _timeline.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final item = _timeline[idx];

        Color badgeColor;
        IconData icon;
        switch (item.tipo) {
          case AuditMovementType.venta:
            badgeColor = const Color(0xFF2E7D32);
            icon = Icons.receipt;
            break;
          case AuditMovementType.ventaCancelada:
            badgeColor = const Color(0xFFC62828);
            icon = Icons.cancel;
            break;
          case AuditMovementType.entradaCaja:
            badgeColor = const Color(0xFF00838F);
            icon = Icons.arrow_downward;
            break;
          case AuditMovementType.salidaCaja:
            badgeColor = const Color(0xFFE65100);
            icon = Icons.arrow_upward;
            break;
          case AuditMovementType.abonoCredito:
            badgeColor = const Color(0xFF4A148C);
            icon = Icons.credit_score;
            break;
        }

        return Card(
          elevation: 0.5,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: badgeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(item.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          if (item.metodoPago != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.metodoPago!,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(item.concepto, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(
                        '${fmt.format(item.fecha)} • Atendió: ${item.usuario ?? "Caja"}',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Text(
                  (item.esEntrada ? '+\$' : '-\$') + item.monto.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: item.esEntrada ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 2: VENTAS Y TICKETS (MASTER-DETAIL) ---
  Widget _buildSalesTab() {
    if (_sales.isEmpty) {
      return _buildEmptyState();
    }

    final isWide = MediaQuery.sizeOf(context).width >= 800;

    return isWide
        ? Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.42,
                child: _buildGroupedSalesList(),
              ),
              const VerticalDivider(width: 1, color: Color(0xFFCFD8DC)),
              Expanded(
                child: _buildTicketInspector(),
              ),
            ],
          )
        : _buildGroupedSalesList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_outlined, size: 54, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No se encontraron ventas para este período o búsqueda.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Prueba ampliando el rango de fechas en la barra superior.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildGroupedSalesList() {
    final Map<String, List<SaleRecord>> grouped = {};
    for (final sale in _sales) {
      final header = _formatDateHeader(sale.fechaVentaLocal);
      grouped.putIfAbsent(header, () => []).add(sale);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: grouped.keys.length,
      itemBuilder: (context, idx) {
        final dayHeader = grouped.keys.elementAt(idx);
        final daySales = grouped[dayHeader]!;
        final dayTotal = daySales.where((s) => !s.isCancelado).fold(0.0, (acc, s) => acc + s.total);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dayHeader, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79))),
                  Text('\$${dayTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E7D32))),
                ],
              ),
            ),
            ...daySales.map((sale) => _buildSaleRow(sale)),
          ],
        );
      },
    );
  }

  Widget _buildSaleRow(SaleRecord sale) {
    final isSelected = _selectedSale?.id == sale.id;
    final timeStr = DateFormat('HH:mm').format(sale.fechaVentaLocal);

    return InkWell(
      onTap: () => _selectSale(sale),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF1F4E79) : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: sale.isCancelado ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                timeStr,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: sale.isCancelado ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.folioTicket,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      decoration: sale.isCancelado ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    sale.clienteNombre,
                    style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sale.notasTicket != null && sale.notasTicket!.isNotEmpty)
                    Text(
                      '📝 ${sale.notasTicket}',
                      style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${sale.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: sale.isCancelado ? Colors.grey : const Color(0xFF1F4E79),
                    decoration: sale.isCancelado ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  sale.isCancelado ? 'CANCELADO' : sale.primaryPaymentMethod,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: sale.isCancelado ? const Color(0xFFC62828) : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketInspector() {
    final sale = _selectedSale;
    if (sale == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text('Selecciona una venta de la lista para ver partidas y comprobante.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detalle del Ticket: ${sale.folioTicket}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
                  Text('${fmt.format(sale.fechaVentaLocal)} • Cajero: ${sale.cajero}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text('Cliente: ${sale.clienteNombre}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Reimprimir'),
                    onPressed: () => _reprintTicket(sale, _selectedDetails),
                  ),
                  const SizedBox(width: 8),
                  if (!sale.isCancelado) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC62828),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Devolución'),
                      onPressed: () => _openPartialRefundDialog(sale, _selectedDetails),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC62828),
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.cancel, size: 16),
                      label: const Text('Cancelar Ticket'),
                      onPressed: () => _cancelSale(sale, _selectedDetails),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (sale.notasTicket != null && sale.notasTicket!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9C4),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFFF176)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.note_alt_outlined, size: 16, color: Color(0xFFF57F17)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Notas del Ticket: ${sale.notasTicket}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 16),
          Expanded(
            child: _isLoadingDetails
                ? const Center(child: CircularProgressIndicator())
                : _selectedDetails.isEmpty
                    ? const Center(child: Text('No hay partidas registradas para este comprobante.'))
                    : ListView.separated(
                        itemCount: _selectedDetails.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = _selectedDetails[idx];
                          final isGranel = (item.cantidad % 1 != 0);
                          final qtyStr = item.cantidad.toStringAsFixed(isGranel ? 3 : 0);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(
                              '$qtyStr x \$${item.precioHistorico.toStringAsFixed(2)} | Subtotal: \$${(item.cantidad * item.precioHistorico).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              '\$${item.totalLinea.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          );
                        },
                      ),
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal: \$${sale.subtotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black54)),
              if (sale.descuentoTotal > 0)
                Text('Descuento: -\$${sale.descuentoTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red)),
              if (sale.ajusteRedondeo != 0.0)
                Text('Redondeo: \$${sale.ajusteRedondeo.toStringAsFixed(2)}', style: const TextStyle(color: Colors.blue)),
              Text('TOTAL: \$${sale.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 3: MOVIMIENTOS DE INVENTARIO ---
  Widget _buildInventoryTab() {
    if (_inventoryMovements.isEmpty) {
      return const Center(child: Text('No hay movimientos de inventario en el período seleccionado.'));
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _inventoryMovements.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, idx) {
        final mov = _inventoryMovements[idx];
        final tipo = (mov['tipo'] as String? ?? 'VENTA').toUpperCase();
        final cant = (mov['cantidad'] as num?)?.toDouble() ?? 0.0;
        final stockAnt = (mov['stock_anterior'] as num?)?.toDouble() ?? 0.0;
        final stockNuevo = (mov['stock_nuevo'] as num?)?.toDouble() ?? 0.0;
        final fechaStr = mov['fecha'] as String? ?? '';
        final dt = DateTime.tryParse(fechaStr)?.toLocal() ?? DateTime.now();

        Color badgeColor;
        switch (tipo) {
          case 'VENTA':
            badgeColor = const Color(0xFF1565C0);
            break;
          case 'ENTRADA':
            badgeColor = const Color(0xFF2E7D32);
            break;
          case 'AJUSTE':
            badgeColor = const Color(0xFFE65100);
            break;
          case 'DEVOLUCION':
            badgeColor = const Color(0xFF6A1B9A);
            break;
          default:
            badgeColor = Colors.grey;
        }

        return Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                  child: Text(tipo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mov['producto_desc'] as String? ?? 'Producto', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        'ID/SKU: ${mov['producto_id']} • Motivo: ${mov['motivo'] ?? "N/A"}',
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                      Text(
                        '${fmt.format(dt)} • Usuario: ${mov['usuario_id'] ?? "Cajero"}',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${cant >= 0 ? "+" : ""}$cant',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: cant >= 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                      ),
                    ),
                    Text(
                      'Stock: $stockAnt -> $stockNuevo',
                      style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- TAB 4: FLUJO DE EFECTIVO Y ABONOS ---
  Widget _buildCashFlowTab() {
    final List<Map<String, dynamic>> combined = [
      ..._cashMovements.map((m) => {...m, 'source': 'caja'}),
      ..._creditPayments.map((ab) => {...ab, 'source': 'credito'}),
    ];

    if (combined.isEmpty) {
      return const Center(child: Text('No hay movimientos de caja ni abonos en el período seleccionado.'));
    }

    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: combined.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, idx) {
        final item = combined[idx];
        final source = item['source'] as String;
        final monto = (item['monto'] as num?)?.toDouble() ?? 0.0;
        final fechaStr = item['fecha'] as String? ?? '';
        final dt = DateTime.tryParse(fechaStr)?.toLocal() ?? DateTime.now();

        if (source == 'credito') {
          return Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFE8EAF6), borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.credit_score, color: Color(0xFF3F51B5), size: 20),
              ),
              title: Text('Abono a Crédito - ${item['cliente_nombre'] ?? "Cliente"}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${fmt.format(dt)} • Registro contable de cobranza', style: const TextStyle(fontSize: 11)),
              trailing: Text('+\$${monto.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2E7D32))),
            ),
          );
        } else {
          final tipo = (item['tipo'] as String? ?? 'entrada').toLowerCase();
          final isEntrada = tipo == 'entrada';
          return Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEntrada ? const Color(0xFFE0F2F1) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isEntrada ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isEntrada ? const Color(0xFF00796B) : const Color(0xFFC62828),
                  size: 20,
                ),
              ),
              title: Text(item['concepto'] as String? ?? 'Movimiento de caja', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text('${fmt.format(dt)} • ${isEntrada ? "Entrada de dinero" : "Salida / Retiro"}', style: const TextStyle(fontSize: 11)),
              trailing: Text(
                (isEntrada ? '+\$' : '-\$') + monto.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isEntrada ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                ),
              ),
            ),
          );
        }
      },
    );
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yest = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yest.year && dt.month == yest.month && dt.day == yest.day;

    final months = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    final days = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];

    if (isToday) {
      return 'Hoy • ${dt.day} de $monthName ${dt.year}';
    } else if (isYesterday) {
      return 'Ayer • ${dt.day} de $monthName ${dt.year}';
    } else {
      return '$dayName, ${dt.day} de $monthName ${dt.year}';
    }
  }
}
