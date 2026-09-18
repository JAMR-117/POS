import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/shift_controller.dart';

class OpenShiftDialog extends StatefulWidget {
  final ShiftController shiftController;
  final String usuarioId;

  const OpenShiftDialog({
    super.key,
    required this.shiftController,
    this.usuarioId = 'cajero-principal',
  });

  static Future<bool> show(BuildContext context, ShiftController controller) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OpenShiftDialog(shiftController: controller),
    );
    return res ?? false;
  }

  @override
  State<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<OpenShiftDialog> {
  final TextEditingController _amountController = TextEditingController(text: '500.00');
  bool _isProcessing = false;
  String? _error;

  Future<void> _handleOpen() async {
    final amount = double.tryParse(_amountController.text) ?? -1.0;
    if (amount < 0) {
      setState(() => _error = 'Ingrese un monto válido.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await widget.shiftController.openShift(
        usuarioId: widget.usuarioId,
        montoInicial: amount,
      );
      if (mounted) Navigator.of(context).pop(true);
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
      title: const Text('Apertura de Caja Requerida', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Para comenzar a registrar tickets es necesario abrir un turno e ingresar el fondo de cambio en efectivo.'),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Monto Inicial en Efectivo (\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onSubmitted: (_) => _handleOpen(),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
          onPressed: _isProcessing ? null : _handleOpen,
          child: _isProcessing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Iniciar Turno'),
        ),
      ],
    );
  }
}