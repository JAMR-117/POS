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
    Color badgeColor;
    String badgeText;

    switch (item.nivelRiesgo) {
      case RiskLevel.critico:
        badgeColor = const Color(0xFFD32F2F);
        badgeText = 'AGOTADO';
        break;
      case RiskLevel.alto:
        badgeColor = const Color(0xFFE65100);
        badgeText = '${item.diasRestantes.toStringAsFixed(1)} DÍAS';
        break;
      case RiskLevel.moderado:
      default:
        badgeColor = const Color(0xFFF57C00);
        badgeText = '${item.diasRestantes.toStringAsFixed(1)} DÍAS';
        break;
    }

    final bool isGranel = (item.stockActual % 1 != 0);
    final String stockFormat = item.stockActual.toStringAsFixed(isGranel ? 3 : 0);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: badgeColor.withValues(alpha: 0.12),
        child: Icon(
          item.nivelRiesgo == RiskLevel.critico ? Icons.error_outline : Icons.warning_amber_rounded,
          color: badgeColor,
        ),
      ),
      title: Text(
        item.descripcion,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          'Stock actual: $stockFormat | Salida diaria: ${item.velocidadDiaria.toStringAsFixed(2)} unid/día',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '30d: ${item.ventasUltimos30Dias.toStringAsFixed(isGranel ? 1 : 0)} vend.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
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