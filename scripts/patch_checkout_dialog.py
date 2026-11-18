content = """import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';
import 'dart:async';

/// Resultado detallado de la liquidación de la venta
class CheckoutResult {
  final double cambio;
  final double ajusteRedondeo;
  final double totalFinal;
  final List<PaymentMethodBreakdown> pagos;

  const CheckoutResult({
    required this.cambio,
    this.ajusteRedondeo = 0.0,
    required this.totalFinal,
    this.pagos = const [],
  });
}

/// Modal para liquidación de ticket con soporte para pagos divididos/mixtos
/// y redondeo inteligente de centavos en efectivo.
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

  bool _roundCents = true;
  bool _isProcessing = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final total = widget.cartController.total;
    // Por defecto sugerir redondeo si es en efectivo
    final initialCash = _roundCents ? total.roundToDouble() : total;
    _cashController.text = initialCash.toStringAsFixed(2);
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
  double get _rawTotalDue => widget.cartController.total;

  // Redondeo aplica exclusivamente cuando se paga en efectivo sin tarjetas ni transferencias
  bool get _isCashOnly => _cardPaid == 0.0 && _transferPaid == 0.0 && _cashPaid > 0.0;

  double get _ajusteRedondeo {
    if (_roundCents && _isCashOnly) {
      final double rounded = _rawTotalDue.roundToDouble();
      return double.parse((rounded - _rawTotalDue).toStringAsFixed(2));
    }
    return 0.0;
  }

  double get _effectiveTotalDue => double.parse((_rawTotalDue + _ajusteRedondeo).toStringAsFixed(2));

  double get _remaining => (_effectiveTotalDue - _totalPaid) > 0 ? (_effectiveTotalDue - _totalPaid) : 0.0;
  double get _change => (_totalPaid > _effectiveTotalDue) ? (_totalPaid - _effectiveTotalDue) : 0.0;
  bool get _isPayable => _totalPaid >= _effectiveTotalDue && _effectiveTotalDue > 0;

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
        totalRecibidoEfectivo: _cashPaid > 0 ? _cashPaid : null,
        ajusteRedondeo: _ajusteRedondeo,
      );

      if (mounted) {
        Navigator.of(context).pop(
          CheckoutResult(
            cambio: cambioEntregado,
            ajusteRedondeo: _ajusteRedondeo,
            totalFinal: _effectiveTotalDue,
            pagos: pagos,
          ),
        );
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
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
                  r'$' + _effectiveTotalDue.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                ),
              ],
            ),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
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

                  // Chip / Switch visual de Redondeo en Efectivo
                  if (_cardPaid == 0.0 && _transferPaid == 0.0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _roundCents ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _roundCents ? const Color(0xFFA5D6A7) : const Color(0xFFE0E0E0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _roundCents ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: _roundCents ? const Color(0xFF2E7D32) : Colors.grey,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Redondear centavos en efectivo',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Switch(
                            value: _roundCents,
                            activeColor: const Color(0xFF2E7D32),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              setState(() {
                                _roundCents = val;
                                if (val) {
                                  _cashController.text = _rawTotalDue.roundToDouble().toStringAsFixed(2);
                                } else {
                                  _cashController.text = _rawTotalDue.toStringAsFixed(2);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  _buildPaymentInput(
                    label: 'Efectivo ($)',
                    controller: _cashController,
                    focusNode: _cashFocusNode,
                    nextFocus: _cardFocusNode,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInput(
                    label: 'Tarjeta Débito/Crédito ($)',
                    controller: _cardController,
                    focusNode: _cardFocusNode,
                    nextFocus: _transferFocusNode,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInput(
                    label: 'Transferencia Bancaria ($)',
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
                        if (_ajusteRedondeo != 0.0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal Ticket:', style: TextStyle(color: Colors.black54, fontSize: 13)),
                              Text(r'$' + _rawTotalDue.toStringAsFixed(2), style: const TextStyle(fontSize: 13, color: Colors.black54)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Ajuste Redondeo (${_ajusteRedondeo < 0 ? "a favor cliente" : "al peso"}):',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _ajusteRedondeo < 0 ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
                                ),
                              ),
                              Text(
                                (_ajusteRedondeo < 0 ? '-' : '+') + r'$' + _ajusteRedondeo.abs().toStringAsFixed(2),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _ajusteRedondeo < 0 ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total a Cobrar:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(r'$' + _effectiveTotalDue.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Pagado:', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(r'$' + _totalPaid.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_remaining > 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Faltante por cubrir:', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                              Text(r'-$' + _remaining.toStringAsFixed(2), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
                            ],
                          ),
                        if (_change > 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('CAMBIO A ENTREGAR:', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 15)),
                              Text(r'$' + _change.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 18)),
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
              prefixText: r'$ ',
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
"""

with open(r'C:\POS\client\lib\presentation\widgets\checkout_dialog.dart', 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print("Updated checkout_dialog.dart")
