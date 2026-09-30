import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/shift_controller.dart';

class ShiftCutDialog extends StatefulWidget {
  final ShiftController shiftController;

  const ShiftCutDialog({super.key, required this.shiftController});

  static void show(BuildContext context, ShiftController controller) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ShiftCutDialog(shiftController: controller),
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.shiftController.loadShiftSummary();
    _cashCountedController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cashCountedController.dispose();
    _cashFocusNode.dispose();
    super.dispose();
  }

  double get _countedCash => double.tryParse(_cashCountedController.text) ?? 0.0;

  Future<void> _handleCloseShiftZ() async {
    final summary = widget.shiftController.currentSummary;
    if (summary == null || _isProcessing) return;

    final discrepancy = _countedCash - summary.totalEfectivoEsperado;
    final discrepancyText = discrepancy == 0
        ? 'Sin diferencia'
        : (discrepancy > 0
            ? 'SOBRANTE: +\$${discrepancy.toStringAsFixed(2)}'
            : 'FALTANTE: -\$${discrepancy.abs().toStringAsFixed(2)}');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmación de Cierre Z', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '¿Está seguro de cerrar el turno de caja de forma definitiva?\n\n'
          '• Efectivo esperado: \$${summary.totalEfectivoEsperado.toStringAsFixed(2)}\n'
          '• Efectivo contado: \$${_countedCash.toStringAsFixed(2)}\n'
          '• Resultado: $discrepancyText\n\n'
          'Esta operación sella el turno e inserta el evento de sincronización contable.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar Turno'),
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
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.shiftController.currentSummary;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isProcessing) Navigator.of(context).pop();
        },
      },
      child: AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Container(
          color: const Color(0xFF1F4E79),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.point_of_sale, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Gestión de Cortes de Caja', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        content: SizedBox(
          width: 520,
          child: summary == null
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 10),
                        color: const Color(0xFFFFEBEE),
                        child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
                      ),
                    TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFF1F4E79),
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF1F4E79),
                      tabs: const [
                        Tab(icon: Icon(Icons.info_outline), text: 'Corte X (Parcial)'),
                        Tab(icon: Icon(Icons.lock_clock), text: 'Corte Z (Cierre)'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 330,
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
      ),
    );
  }

  Widget _buildCorteXTab(dynamic summary) {
    return ListView(
      children: [
        _buildMetricTile('Fondo Inicial de Caja:', '\$${summary.montoInicial.toStringAsFixed(2)}'),
        const Divider(height: 12),
        _buildMetricTile('Ventas en Efectivo:', '\$${summary.ventasEfectivo.toStringAsFixed(2)}'),
        _buildMetricTile('Ventas con Tarjeta:', '\$${summary.ventasTarjeta.toStringAsFixed(2)}'),
        _buildMetricTile('Ventas por Transferencia:', '\$${summary.ventasTransferencia.toStringAsFixed(2)}'),
        const Divider(height: 12),
        _buildMetricTile('Total de Tickets Emitidos:', '${summary.totalTickets}'),
        _buildMetricTile('Total Ingresos por Ventas:', '\$${summary.totalVentas.toStringAsFixed(2)}', isBold: true),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(4)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('EFECTIVO TEÓRICO EN CAJÓN:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0D47A1))),
              Text('\$${summary.totalEfectivoEsperado.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0D47A1))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCorteZTab(dynamic summary) {
    final discrepancy = _countedCash - summary.totalEfectivoEsperado;
    final hasDiscrepancy = _cashCountedController.text.isNotEmpty;

    Color badgeColor = Colors.grey;
    String badgeText = 'Sin conteo';

    if (hasDiscrepancy) {
      if (discrepancy == 0) {
        badgeColor = const Color(0xFF2E7D32);
        badgeText = 'EXACTO (\$0.00)';
      } else if (discrepancy > 0) {
        badgeColor = const Color(0xFF0288D1);
        badgeText = 'SOBRANTE: +\$${discrepancy.toStringAsFixed(2)}';
      } else {
        badgeColor = const Color(0xFFD32F2F);
        badgeText = 'FALTANTE: -\$${discrepancy.abs().toStringAsFixed(2)}';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Efectivo Esperado en Cajón:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('\$${summary.totalEfectivoEsperado.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
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
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: badgeColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Discrepancia Arqueo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(badgeText, style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD32F2F),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: (_cashCountedController.text.isEmpty || _isProcessing) ? null : _handleCloseShiftZ,
          child: _isProcessing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('EJECUTAR CORTE Z Y CERRAR TURNO', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String val, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}