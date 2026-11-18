import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/shift_controller.dart';
import '../../data/repositories/shift_repository.dart';

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
  ShiftSummary? _summary;
  bool _isLoadingSummary = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _montoController.addListener(() => setState(() {}));
    _conceptoController.addListener(() => setState(() {}));
  }

  Future<void> _loadSummary() async {
    try {
      final s = await widget.shiftController.loadShiftSummary();
      if (mounted) {
        setState(() {
          _summary = s;
          _isLoadingSummary = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSummary = false);
    }
  }

  @override
  void dispose() {
    _montoController.dispose();
    _conceptoController.dispose();
    _montoFocusNode.dispose();
    _conceptoFocusNode.dispose();
    super.dispose();
  }

  double get _efectivoDisponible => _summary?.totalEfectivoEsperado ?? 0.0;

  String? get _montoError {
    final text = _montoController.text.trim();
    if (text.isEmpty) return null;
    final monto = double.tryParse(text) ?? 0.0;
    if (monto <= 0) return 'El monto debe ser mayor a \$0.00';
    if (_tipoMovimiento == 'salida' && monto > _efectivoDisponible + 0.001) {
      return 'El retiro no puede superar el efectivo disponible (\$$_efectivoDisponibleFormatted)';
    }
    return null;
  }

  String? get _conceptoError {
    final text = _conceptoController.text.trim();
    if (text.isEmpty) return null;
    if (text.length < 3) return 'El concepto debe tener al menos 3 caracteres';
    return null;
  }

  String get _efectivoDisponibleFormatted => '\$${_efectivoDisponible.toStringAsFixed(2)}';

  bool get _canSave {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    final concepto = _conceptoController.text.trim();
    if (monto <= 0) return false;
    if (concepto.length < 3) return false;
    if (_tipoMovimiento == 'salida' && monto > _efectivoDisponible + 0.001) return false;
    if (_isProcessing) return false;
    return true;
  }

  Future<void> _handleSave() async {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    final concepto = _conceptoController.text.trim();

    if (monto <= 0) {
      setState(() => _error = 'Ingrese un monto válido mayor a cero.');
      _montoFocusNode.requestFocus();
      return;
    }
    if (concepto.length < 3) {
      setState(() => _error = 'El concepto debe contener al menos 3 caracteres.');
      _conceptoFocusNode.requestFocus();
      return;
    }
    if (_tipoMovimiento == 'salida' && monto > _efectivoDisponible + 0.001) {
      setState(() => _error = 'No puede retirar más efectivo del disponible en caja ($_efectivoDisponibleFormatted).');
      _montoFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
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
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Registre entradas o retiros manuales. Esta operación ajustará inmediatamente el efectivo teórico esperado en su Corte X/Z.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                
                // Indicador de Efectivo Disponible en Turno Activo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _tipoMovimiento == 'salida' ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _tipoMovimiento == 'salida' ? Colors.orange.shade300 : Colors.green.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _tipoMovimiento == 'salida' ? Icons.account_balance_wallet : Icons.savings,
                            size: 18,
                            color: _tipoMovimiento == 'salida' ? Colors.orange.shade900 : Colors.green.shade900,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Efectivo disponible en caja:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _tipoMovimiento == 'salida' ? Colors.orange.shade900 : Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                      _isLoadingSummary
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              _efectivoDisponibleFormatted,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _tipoMovimiento == 'salida' ? Colors.orange.shade900 : Colors.green.shade900,
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

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
                const SizedBox(height: 16),
                TextField(
                  controller: _montoController,
                  focusNode: _montoFocusNode,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Monto (\$)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                    errorText: _montoError,
                  ),
                  onSubmitted: (_) => _conceptoFocusNode.requestFocus(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _conceptoController,
                  focusNode: _conceptoFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Concepto (Mínimo 3 caracteres, ej. Pago de luz)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.description_outlined),
                    errorText: _conceptoError,
                  ),
                  onSubmitted: (_) {
                    if (_canSave) _handleSave();
                  },
                ),
              ],
            ),
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
              backgroundColor: _canSave ? const Color(0xFF1F4E79) : Colors.grey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: _isProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('REGISTRAR MOVIMIENTO [ENTER]', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _canSave ? _handleSave : null,
          ),
        ],
      ),
    );
  }
}
