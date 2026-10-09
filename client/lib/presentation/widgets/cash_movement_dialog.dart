import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/shift_controller.dart';

class CashMovementDialog extends StatefulWidget {
  final ShiftController shiftController;

  const CashMovementDialog({super.key, required this.shiftController});

  static Future<void> show(BuildContext context, ShiftController controller) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashMovementDialog(shiftController: controller),
    );
  }

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final TextEditingController _montoController = TextEditingController();
  final TextEditingController _conceptoController = TextEditingController();
  
  final FocusNode _montoFocusNode = FocusNode();
  final FocusNode _conceptoFocusNode = FocusNode();

  String _tipoMovimiento = 'salida'; 
  bool _isProcessing = false;
  String? _error;

  @override
  void dispose() {
    _montoController.dispose();
    _conceptoController.dispose();
    _montoFocusNode.dispose();
    _conceptoFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    final concepto = _conceptoController.text.trim();

    if (monto <= 0) {
      setState(() => _error = 'Ingrese un monto válido mayor a cero.');
      _montoFocusNode.requestFocus();
      return;
    }
    if (concepto.isEmpty) {
      setState(() => _error = 'El concepto es obligatorio para la auditoría de caja.');
      _conceptoFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Nota: Verifica que la firma de tu controlador coincida. 
      // Si usas parámetros nombrados (tipo:, monto:, concepto:), ajusta la llamada:
      await widget.shiftController.registerCashMovement(
        _tipoMovimiento, 
        monto, 
        concepto
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tipoMovimiento == 'salida' 
              ? 'Retiro registrado. El efectivo esperado en caja disminuyó.' 
              : 'Entrada registrada. El efectivo esperado en caja aumentó.'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 4),
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
                  Icon(Icons.swap_horiz, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Movimiento de Efectivo', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
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
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Registre entradas o retiros manuales. Esta operación ajustará inmediatamente el efectivo teórico esperado en su Corte X/Z.',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 12),
                  color: const Color(0xFFFFEBEE),
                  child: Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
                ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'salida', label: Text('Retiro (Gasto)'), icon: Icon(Icons.arrow_upward)),
                  ButtonSegment(value: 'entrada', label: Text('Entrada (Fondo)'), icon: Icon(Icons.arrow_downward)),
                ],
                selected: {_tipoMovimiento},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() => _tipoMovimiento = newSelection.first);
                  _montoFocusNode.requestFocus();
                },
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _montoController,
                focusNode: _montoFocusNode,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: 'Monto (\$)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                onSubmitted: (_) => _conceptoFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _conceptoController,
                focusNode: _conceptoFocusNode,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Concepto (Ej. Pago de luz, Fondo extra)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                onSubmitted: (_) => _handleSave(),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar [ESC]'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: _isProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('REGISTRAR MOVIMIENTO [ENTER]', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _isProcessing ? null : _handleSave,
          ),
        ],
      ),
    );
  }
}