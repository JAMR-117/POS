import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum InsufficientStockDecision {
  adjustToLimit,
  allowNegative,
}

/// Modal de decisión rápida con soporte para teclado (Enter / Esc) y ratón
class InsufficientStockDialog extends StatelessWidget {
  final String productName;
  final double currentStock;
  final double requestedQuantity;
  final String? location;

  const InsufficientStockDialog({
    super.key,
    required this.productName,
    required this.currentStock,
    required this.requestedQuantity,
    this.location,
  });

  static Future<InsufficientStockDecision?> show({
    required BuildContext context,
    required String productName,
    required double currentStock,
    required double requestedQuantity,
    String? location,
  }) {
    return showDialog<InsufficientStockDecision>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => InsufficientStockDialog(
        productName: productName,
        currentStock: currentStock,
        requestedQuantity: requestedQuantity,
        location: location,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double resultingStock = currentStock - requestedQuantity;
    final String limitLabel = currentStock <= 0 ? '0 pzs (No agregar)' : '${_fmt(currentStock)} pzs';

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            Navigator.of(context).pop(InsufficientStockDecision.allowNegative);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop(InsufficientStockDecision.adjustToLimit);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Inventario Insuficiente',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF263238)),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F4E79)),
              ),
              if (location != null && location!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.brown),
                    const SizedBox(width: 4),
                    Text('Ubicación: $location', style: TextStyle(fontSize: 12, color: Colors.brown.shade800, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Existencia actual en sistema:', style: TextStyle(fontSize: 13)),
                        Text(
                          '${_fmt(currentStock)} pzs',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: currentStock <= 0 ? Colors.red.shade700 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cantidad solicitada:', style: TextStyle(fontSize: 13)),
                        Text(
                          '${_fmt(requestedQuantity)} pzs',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Balance proyectado:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${_fmt(resultingStock)} pzs (Negativo)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'El inventario actual no cubre la cantidad solicitada. Puedes ajustar al límite disponible o autorizar la venta en negativo.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              side: BorderSide(color: Colors.grey.shade400),
            ),
            onPressed: () => Navigator.of(context).pop(InsufficientStockDecision.adjustToLimit),
            child: Text(
              'No continuar / Ajustar ($limitLabel) [Esc]',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () => Navigator.of(context).pop(InsufficientStockDecision.allowNegative),
            child: const Text(
              'Continuar con la venta (Dejar en negativo) [Enter]',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double n) => n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}
