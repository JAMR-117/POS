import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/business_config.dart';
import '../../data/local/models.dart';
import '../../data/repositories/client_repository.dart';
import '../controllers/cart_controller.dart';
import 'dart:async';

/// Resultado detallado de la liquidación de la venta
class CheckoutResult {
  final double cambio;
  final double ajusteRedondeo;
  final double totalFinal;
  final List<PaymentMethodBreakdown> pagos;
  final String? notasTicket;

  const CheckoutResult({
    required this.cambio,
    this.ajusteRedondeo = 0.0,
    required this.totalFinal,
    this.pagos = const [],
    this.notasTicket,
  });
}

/// Modal para liquidación de ticket con soporte para pagos divididos/mixtos,
/// redondeo inteligente de centavos en efectivo y blindaje estricto de crédito y pagos electrónicos.
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
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final FocusNode _cashFocusNode = FocusNode();
  final FocusNode _cardFocusNode = FocusNode();
  final FocusNode _transferFocusNode = FocusNode();
  final FocusNode _creditFocusNode = FocusNode();

  final ClientRepository _clientRepo = ClientRepository();
  Cliente? _currentClient;

  bool _roundCents = true;
  bool _isProcessing = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    final total = widget.cartController.total;
    // Por defecto sugerir redondeo si es en efectivo según 3 rangos comerciales (.10 / .50 / .60)
    final initialCash = _roundCents ? calcularRedondeoEfectivo(total) : total;
    _cashController.text = initialCash.toStringAsFixed(2);
    _cashController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _cashController.text.length,
    );

    _loadClientData();

    // Escuchadores reactivos para recalcular cambios y saldos al vuelo
    _cashController.addListener(_onAmountChanged);
    _cardController.addListener(_onAmountChanged);
    _transferController.addListener(_onAmountChanged);
    _creditController.addListener(_onAmountChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cashFocusNode.requestFocus();
    });
  }

  Future<void> _loadClientData() async {
    final clientId = widget.cartController.currentClientId;
    if (clientId != 'PUBLICO-GRAL' && clientId.isNotEmpty) {
      try {
        final clients = await _clientRepo.getClients();
        final match = clients.where((c) => c.id == clientId).toList();
        if (mounted && match.isNotEmpty) {
          setState(() {
            _currentClient = match.first;
          });
          return;
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cardController.dispose();
    _transferController.dispose();
    _creditController.dispose();
    _notesController.dispose();
    _cashFocusNode.dispose();
    _cardFocusNode.dispose();
    _transferFocusNode.dispose();
    _creditFocusNode.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    setState(() {});
  }

  double get _cashPaid => double.tryParse(_cashController.text) ?? 0.0;
  double get _cardPaid => double.tryParse(_cardController.text) ?? 0.0;
  double get _transferPaid => double.tryParse(_transferController.text) ?? 0.0;
  double get _creditPaid => double.tryParse(_creditController.text) ?? 0.0;

  double get _totalPaid => _cashPaid + _cardPaid + _transferPaid + _creditPaid;
  double get _rawTotalDue => widget.cartController.total;

  // Redondeo aplica exclusivamente cuando se paga en efectivo sin tarjetas, transferencias ni créditos
  bool get _isCashOnly => _cardPaid == 0.0 && _transferPaid == 0.0 && _creditPaid == 0.0 && _cashPaid > 0.0;

  double get _ajusteRedondeo {
    if (_roundCents && _isCashOnly) {
      return calcularAjusteRedondeo(_rawTotalDue);
    }
    return 0.0;
  }

  double get _effectiveTotalDue => double.parse((_rawTotalDue + _ajusteRedondeo).toStringAsFixed(2));

  double get _remaining => (_effectiveTotalDue - _totalPaid) > 0 ? (_effectiveTotalDue - _totalPaid) : 0.0;
  double get _change => (_totalPaid > _effectiveTotalDue) ? (_totalPaid - _effectiveTotalDue) : 0.0;

  // Validaciones estrictas de integridad financiera
  String? get _electronicPaymentError {
    final electronic = _cardPaid + _transferPaid;
    if (electronic > _effectiveTotalDue + 0.001) {
      return 'El pago con tarjeta/transferencia (\$${electronic.toStringAsFixed(2)}) excede el total a pagar (\$${_effectiveTotalDue.toStringAsFixed(2)}). No se permite cambio en efectivo sobre pagos electrónicos.';
    }
    return null;
  }

  String? get _creditPaymentError {
    if (_creditPaid <= 0) return null;
    if (!BusinessConfig.current.creditoClientesHabilitado) {
      return 'El crédito a clientes está deshabilitado globalmente en Configuración.';
    }
    final clientId = widget.cartController.currentClientId;
    if (clientId == 'PUBLICO-GRAL') {
      return 'Prohibido cobrar a crédito a "Público en General". Asigne un cliente registrado para habilitar crédito.';
    }
    if (_creditPaid > _effectiveTotalDue + 0.001) {
      return 'El monto a crédito (\$${_creditPaid.toStringAsFixed(2)}) no puede superar el total por pagar (\$${_effectiveTotalDue.toStringAsFixed(2)}).';
    }
    if (_currentClient != null && _currentClient!.limiteCredito > 0) {
      final totalDeudaProyectada = _currentClient!.saldoDeudor + _creditPaid;
      if (totalDeudaProyectada > _currentClient!.limiteCredito + 0.001) {
        final exceso = totalDeudaProyectada - _currentClient!.limiteCredito;
        return 'Excede el límite de crédito (\$${_currentClient!.limiteCredito.toStringAsFixed(2)}). Deuda actual: \$${_currentClient!.saldoDeudor.toStringAsFixed(2)} + Crédito: \$${_creditPaid.toStringAsFixed(2)} -> Exceso: \$${exceso.toStringAsFixed(2)}';
      }
    }
    return null;
  }

  bool get _isPayable {
    if (_isProcessing) return false;
    if (_effectiveTotalDue <= 0) return false;
    if (_totalPaid < _effectiveTotalDue) return false;
    if (_electronicPaymentError != null) return false;
    if (_creditPaymentError != null) return false;
    return true;
  }

  Future<void> _processCheckout() async {
    if (!_isPayable || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _localError = null;
    });

    final List<PaymentMethodBreakdown> pagos = [];
    if (_cashPaid > 0) {
      final efectivoRegistrado = (_cashPaid - _change).clamp(0.0, _cashPaid);
      pagos.add(PaymentMethodBreakdown(metodo: 'efectivo', monto: efectivoRegistrado));
    }
    if (_cardPaid > 0) {
      pagos.add(PaymentMethodBreakdown(metodo: 'tarjeta', monto: _cardPaid));
    }
    if (_transferPaid > 0) {
      pagos.add(PaymentMethodBreakdown(metodo: 'transferencia', monto: _transferPaid));
    }
    if (_creditPaid > 0) {
      pagos.add(PaymentMethodBreakdown(metodo: 'credito', monto: _creditPaid));
    }

    // Snapshot inmutable antes de que cartController.checkout() vacie _items
    final double finalTotalToPay = _effectiveTotalDue;
    final double finalChangeExpected = _change;
    final double finalAjusteRedondeo = _ajusteRedondeo;
    final rawNotas = _notesController.text.trim();
    final String? notasParam = rawNotas.isNotEmpty ? rawNotas : null;

    try {
      final cambioEntregado = await widget.cartController.checkout(
        pagos: pagos,
        corteCajaId: widget.corteCajaId,
        totalRecibidoEfectivo: _cashPaid > 0 ? _cashPaid : null,
        ajusteRedondeo: _ajusteRedondeo,
        notasTicket: notasParam,
      );

      if (mounted) {
        Navigator.of(context).pop(
          CheckoutResult(
            cambio: cambioEntregado > 0 ? cambioEntregado : finalChangeExpected,
            ajusteRedondeo: finalAjusteRedondeo,
            totalFinal: finalTotalToPay,
            pagos: pagos,
            notasTicket: notasParam,
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
    final isPublicClient = widget.cartController.currentClientId == 'PUBLICO-GRAL';
    final creditConfigEnabled = BusinessConfig.current.creditoClientesHabilitado;
    final creditAllowed = creditConfigEnabled && !isPublicClient;
    final creditLabel = !creditConfigEnabled
        ? 'Venta a Crédito (Deshabilitado en Configuración)'
        : (isPublicClient ? 'Venta a Crédito (Deshabilitado: Público General)' : 'Venta a Crédito');

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIQUIDACIÓN DE TICKET',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Row(
                      children: [
                        Icon(
                          isPublicClient ? Icons.storefront : Icons.person,
                          size: 14,
                          color: isPublicClient ? Colors.grey : const Color(0xFF1F4E79),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.cartController.currentClientNombre,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isPublicClient ? Colors.grey : const Color(0xFF1F4E79)),
                        ),
                        if (_currentClient != null && _currentClient!.limiteCredito > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Text(
                              '(Límite Crédito: \$${_currentClient!.limiteCredito.toStringAsFixed(2)} | Deuda: \$${_currentClient!.saldoDeudor.toStringAsFixed(2)})',
                              style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                            ),
                          ),
                      ],
                    ),
                  ],
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

                  if (_electronicPaymentError != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _electronicPaymentError!,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_creditPaymentError != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        border: Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _creditPaymentError!,
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Chip / Switch visual de Redondeo en Efectivo
                  if (_cardPaid == 0.0 && _transferPaid == 0.0 && _creditPaid == 0.0) ...[
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
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  _roundCents ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: _roundCents ? const Color(0xFF2E7D32) : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Redondeo en efectivo (.10 / .50 / .60)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _roundCents,
                            activeTrackColor: const Color(0xFF2E7D32),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) {
                              setState(() {
                                _roundCents = val;
                                if (val) {
                                  _cashController.text = calcularRedondeoEfectivo(_rawTotalDue).toStringAsFixed(2);
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
                    label: 'Efectivo',
                    controller: _cashController,
                    focusNode: _cashFocusNode,
                    nextFocus: _cardFocusNode,
                    icon: Icons.payments_outlined,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInput(
                    label: 'Tarjeta Débito/Crédito',
                    controller: _cardController,
                    focusNode: _cardFocusNode,
                    nextFocus: _transferFocusNode,
                    icon: Icons.credit_card,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInput(
                    label: 'Transferencia Bancaria',
                    controller: _transferController,
                    focusNode: _transferFocusNode,
                    nextFocus: _creditFocusNode,
                    icon: Icons.account_balance,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInput(
                    label: creditLabel,
                    controller: _creditController,
                    focusNode: _creditFocusNode,
                    nextFocus: null,
                    enabled: creditAllowed,
                    icon: Icons.request_quote,
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
                              const Text('Cambio a Entregar:', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(r'$' + _change.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '📝 Notas / Observaciones en el Ticket (Opcional):',
                      hintText: 'Ej. Entregar en mostrador 2, Garantía 30 días, etc.',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
              child: const Text('CANCELAR [ESC]', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPayable ? const Color(0xFF1F4E79) : Colors.grey.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 0,
              ),
              onPressed: _isPayable ? _processCheckout : null,
              child: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('COBRAR [ENTER]', style: TextStyle(fontWeight: FontWeight.bold)),
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
    bool enabled = true,
    IconData? icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: enabled ? null : Colors.grey),
          prefixText: r'$ ',
          prefixIcon: icon != null ? Icon(icon, size: 18, color: enabled ? const Color(0xFF1F4E79) : Colors.grey) : null,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onSubmitted: (_) {
          if (nextFocus != null) {
            nextFocus.requestFocus();
          } else if (_isPayable && !_isProcessing) {
            _processCheckout();
          }
        },
      ),
    );
  }
}
