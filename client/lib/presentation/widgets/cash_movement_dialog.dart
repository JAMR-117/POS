import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/shift_controller.dart';

class CashMovementDialog extends StatefulWidget {
  final ShiftController shiftController;

  const CashMovementDialog({super.key, required this.shiftController});

  static Future<bool> show(BuildContext context, ShiftController controller) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashMovementDialog(shiftController: controller),
    );
    return result ?? false;
  }

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final TextEditingController _montoController = TextEditingController();
  final TextEditingController _conceptoController = TextEditingController();
  
  String _tipoMovimiento = 'salida'; 
  bool _isProcessing = false;
  String? _error;

  @override
  void dispose() {
    _montoController.dispose();
    _conceptoController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    final concepto = _conceptoController.text.trim();

    if (monto <= 0) {
      setState(() => _error = 'Ingrese un monto válido mayor a cero.');
      return;
    }
    if (concepto.isEmpty) {
      setState(() => _error = 'El concepto/motivo es estrictamente obligatorio.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await widget.shiftController.registerCashMovement(
        tipo: _tipoMovimiento,
        monto: monto,
        concepto: concepto,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tipoMovimiento == 'salida' 
                ? 'Retiro registrado. El efectivo esperado ha disminuido.' 
                : 'Entrada registrada. El efectivo esperado ha aumentado.'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _tipoMovimiento == 'salida' ? Icons.money_off : Icons.attach_money, 
            color: const Color(0xFF1F4E79),
          ),
          const SizedBox(width: 8),
          const Text('Movimiento de Caja', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.red.shade50,
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'salida', label: Text('Retiro (Salida)'), icon: Icon(Icons.arrow_upward)),
                ButtonSegment(value: 'entrada', label: Text('Fondo (Entrada)'), icon: Icon(Icons.arrow_downward)),
              ],
              selected: {_tipoMovimiento},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _tipoMovimiento = newSelection.first);
              },
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _montoController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Monto (\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _conceptoController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Concepto (Obligatorio)',
                hintText: 'Ej. Pago de agua, Retiro de exceso...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description_outlined),
              ),
              onSubmitted: (_) => _handleSave(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F4E79),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _isProcessing ? null : _handleSave,
          child: _isProcessing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('REGISTRAR MOVIMIENTO'),
        ),
      ],
    );
  }
}