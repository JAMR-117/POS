import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';
import 'dart:async';

/// Modal para liquidación de ticket con soporte para pagos divididos/mixtos.
class CheckoutDialog extends StatefulWidget {
  final CartController cartController;
  final String corteCajaId;

  const CheckoutDialog({
    super.key,
    required this.cartController,
    required this.corteCajaId,
  });

  @override
  State<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<CheckoutDialog> {
  final TextEditingController _cashController = TextEditingController();
  final TextEditingController _cardController = TextEditingController();
  final TextEditingController _transferController = TextEditingController();

  final FocusNode _cashFocusNode = FocusNode();
  final FocusNode _cardFocusNode = FocusNode();
  final FocusNode _transferFocusNode = FocusNode();

  bool _isProcessing = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    // Por defecto, sugerir el cobro total en efectivo para rapidez
    final total = widget.cartController.total;
    _cashController.text = total.toStringAsFixed(2);
    _cashController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _cashController.text.length,
    );

    // Escuchadores reactivos para recalcular cambios y saldos al vuelo
    _cashController.addListener(_onAmountChanged);
    _cardController.addListener(_onAmountChanged);
    _transferController.addListener(_onAmountChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cashFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cardController.dispose();
    _transferController.dispose();
    _cashFocusNode.dispose();
    _cardFocusNode.dispose();
    _transferFocusNode.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    setState(() {});
  }

  double get _cashPaid => double.tryParse(_cashController.text) ?? 0.0;
  double get _cardPaid => double.tryParse(_cardController.text) ?? 0.0;
  double get _transferPaid => double.tryParse(_transferController.text) ?? 0.0;

  double get _totalPaid => _cashPaid + _cardPaid + _transferPaid;
  double get _totalDue => widget.cartController.total;

  double get _remaining => (_totalDue - _totalPaid) > 0 ? (_totalDue - _totalPaid) : 0.0;
  double get _change => (_totalPaid > _totalDue) ? (_totalPaid - _totalDue) : 0.0;
  bool get _isPayable => _totalPaid >= _totalDue && _totalDue > 0;

  Future<void> _processCheckout() async {
    if (!_isPayable || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _localError = null;
    });

    final List<PaymentMethodBreakdown> pagos = [];
    if (_cashPaid > 0) {
      // Si hubo sobrepago en efectivo, registramos el efectivo neto absorbido
      final efectivoRegistrado = (_cashPaid - _change).clamp(0.0, _cashPaid);
      pagos.add(PaymentMethodBreakdown(metodo: 'efectivo', monto: efectivoRegistrado));
    }
    if (_cardPaid > 0) {
      pagos.add(PaymentMethodBreakdown(metodo: 'tarjeta', monto: _cardPaid));
    }
    if (_transferPaid > 0) {
      pagos.add(PaymentMethodBreakdown(metodo: 'transferencia', monto: _transferPaid));
    }

    try {
      final cambioEntregado = await widget.cartController.checkout(
        pagos: pagos,
        corteCajaId: widget.corteCajaId,
      );

      if (mounted) {
        Navigator.of(context).pop(cambioEntregado);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _localError = e.toString().replaceAll('Exception: ', '');
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
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_isPayable && !_isProcessing) _processCheckout();
        },
      },
      child: FocusScope(
        autofocus: true,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
          contentPadding: const EdgeInsets.all(20.0),
          title: Container(
            padding: const EdgeInsets.only(bottom: 8.0),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFD9D9D9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LIQUIDACIÓN DE TICKET',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                Text(
                  '\$${_totalDue.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_localError != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: const Color(0xFFFFEBEE),
                    child: Text(
                      _localError!,
                      style: const TextStyle(color: Color(0xFFC62828), fontSize: 13),
                    ),
                  ),
                _buildPaymentInput(
                  label: 'Efectivo (\$)',
                  controller: _cashController,
                  focusNode: _cashFocusNode,
                  nextFocus: _cardFocusNode,
                ),
                const SizedBox(height: 8),
                _buildPaymentInput(
                  label: 'Tarjeta Débito/Crédito (\$)',
                  controller: _cardController,
                  focusNode: _cardFocusNode,
                  nextFocus: _transferFocusNode,
                ),
                const SizedBox(height: 8),
                _buildPaymentInput(
                  label: 'Transferencia Bancaria (\$)',
                  controller: _transferController,
                  focusNode: _transferFocusNode,
                  nextFocus: null,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Pagado:', style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('\$${_totalPaid.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_remaining > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Faltante por cubrir:', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                            Text('-\$${_remaining.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      if (_change > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('CAMBIO A ENTREGAR:', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('\$${_change.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                    ],
                  ),
                
                ),
              ],
            ),
            ),
          ),
          actionsPadding: const EdgeInsets.all(16.0),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar [ESC]'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F4E79),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: (_isPayable && !_isProcessing) ? _processCheckout : null,
              child: _isProcessing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Completar Venta [ENTER]', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInput({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
            onSubmitted: (_) {
              if (nextFocus != null) {
                nextFocus.requestFocus();
              } else if (_isPayable) {
                _processCheckout();
              }
            },
          ),
        ),
      ],
    );
  }
}