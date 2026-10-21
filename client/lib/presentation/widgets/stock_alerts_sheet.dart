import 'package:flutter/material.dart';
import '../../data/inventory/inventory_api_client.dart';
import '../controllers/alerts_controller.dart';

class StockAlertsSheet extends StatelessWidget {
  final AlertsController alertsController;

  const StockAlertsSheet({super.key, required this.alertsController});

  /// Abre el panel lateral anclado sin congelar la caja
  static void show(BuildContext context, AlertsController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StockAlertsSheet(alertsController: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          Expanded(
            child: AnimatedBuilder(
              animation: alertsController,
              builder: (context, _) {
                if (alertsController.isLoading && alertsController.alerts.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (alertsController.errorMessage != null && alertsController.alerts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            alertsController.errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black87),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => alertsController.loadAlerts(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (alertsController.alerts.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF2E7D32)),
                        SizedBox(height: 12),
                        Text(
                          'Sin riesgos de desabasto',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Todos los productos de alta rotación tienen suficiente stock.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: alertsController.alerts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final item = alertsController.alerts[index];
                    return _buildAlertTile(item);
                  },
                );
              },
            ),
          ),
          _buildSummaryFooter(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.insights, color: Color(0xFF1F4E79)),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alertas Predictivas de Inventario',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Priorizadas por mayor rotación de venta (últimos 30 días)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar métricas',
            onPressed: () => alertsController.loadAlerts(),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertTile(StockAlertItem item) {
    final bool isAgotado = item.stockActual <= 0;
    final bool isBajoMinimo = item.stockActual <= item.stockMinimo;
    
    Color badgeColor;
    String badgeText;
    if (isAgotado) {
      badgeColor = const Color(0xFFD32F2F);
      badgeText = '¡AGOTADO!';
    } else if (isBajoMinimo) {
      badgeColor = const Color(0xFFE65100);
      badgeText = 'BAJO MÍNIMO';
    } else {
      badgeColor = const Color(0xFFF57C00);
      badgeText = '${item.diasRestantes.toStringAsFixed(1)} DÍAS RESTANTES';
    }

    final bool isGranel = (item.stockActual % 1 != 0);
    final String stockFmt = item.stockActual.toStringAsFixed(isGranel ? 2 : 0);
    final String minFmt = item.stockMinimo.toStringAsFixed(0);
    final String v30dFmt = item.ventasUltimos30Dias.toStringAsFixed(isGranel ? 1 : 0);
    final String totFmt = item.totalUnidadesVendidas.toStringAsFixed(isGranel ? 1 : 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isAgotado ? const Color(0xFFFFEBEE) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAgotado ? Colors.red.shade300 : Colors.grey.shade300,
            width: isAgotado ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.descripcion,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF263238)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Text(
                    '🔥 Vendidos (30d): $v30dFmt pzs',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Histórico: $totFmt pzs',
                  style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                if (item.velocidadDiaria > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${item.velocidadDiaria.toStringAsFixed(1)} pzs/día)',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    children: [
                      const TextSpan(text: 'Stock Actual: '),
                      TextSpan(
                        text: isAgotado ? '¡AGOTADO! ($stockFmt pzs)' : '$stockFmt pzs',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isAgotado ? Colors.red.shade800 : (isBajoMinimo ? Colors.orange.shade900 : Colors.green.shade800),
                        ),
                      ),
                      TextSpan(text: '  vs  Mínimo: $minFmt pzs', style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                const Spacer(),
                if (item.ubicacion != null && item.ubicacion!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEBE9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.brown.shade300),
                    ),
                    child: Text(
                      '📍 ${item.ubicacion}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown.shade800),
                    ),
                  ),
                ],
                if (item.codigoEquivalencia != null && item.codigoEquivalencia!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Text(
                      '🔗 ${item.codigoEquivalencia}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryFooter(ThemeData theme) {
    return Container(
      color: const Color(0xFFF8F9FA),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AnimatedBuilder(
            animation: alertsController,
            builder: (context, _) {
              return Text(
                'Críticos: ${alertsController.criticalCount} | Por agotar: ${alertsController.warningCount}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              );
            },
          ),
          const Text(
            'Motor BI Offline-First',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}