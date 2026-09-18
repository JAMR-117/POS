import 'package:flutter/material.dart';
import '../controllers/alerts_controller.dart';
import 'stock_alerts_sheet.dart';

class StockAlertsButton extends StatelessWidget {
  final AlertsController alertsController;

  const StockAlertsButton({super.key, required this.alertsController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: alertsController,
      builder: (context, _) {
        final count = alertsController.totalAlertsCount;
        final hasCritical = alertsController.criticalCount > 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_active_outlined,
                color: count > 0
                    ? (hasCritical ? const Color(0xFFD32F2F) : const Color(0xFFE65100))
                    : Colors.grey.shade600,
              ),
              tooltip: 'Alertas predictivas de inventario',
              onPressed: () => StockAlertsSheet.show(context, alertsController),
            ),
            if (count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hasCritical ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  } 
}