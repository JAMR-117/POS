import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../../data/repositories/inventory_repository.dart';
import '../controllers/auth_controller.dart';
import 'admin_auth_dialog.dart';

class StockAdjustmentDialog extends StatefulWidget {
  final Product product;
  final AuthController authController;

  const StockAdjustmentDialog({
    super.key,
    required this.product,
    required this.authController,
  });

  static Future<bool> show(BuildContext context, Product product, AuthController auth) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustmentDialog(product: product, authController: auth),
    );
    return result ?? false;
  }

  @override
  State<StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _physicalStockController = TextEditingController();
  final InventoryRepository _inventoryRepo = InventoryRepository();

  String? _selectedReason;
  double _difference = 0.0;
  bool _isProcessing = false;

  final List<String> _motivos = [
    'Ajuste de Conteo',
    'Merma',
    'Caducidad',
    'Robo',
    'Daño Físico'
  ];

  @override
  void initState() {
    super.initState();
    _physicalStockController.addListener(_calculateDifference);
  }

  @override
  void dispose() {
    _physicalStockController.dispose();
    super.dispose();
  }

  void _calculateDifference() {
    final physical = double.tryParse(_physicalStockController.text) ?? widget.product.stockActual;
    setState(() {
      _difference = physical - widget.product.stockActual;
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate() || _selectedReason == null) return;

    // 1. RBAC: Exigir permisos de Administrador antes de afectar inventario
    final isAuthorized = await AdminAuthDialog.requestAdminAccess(context, widget.authController);
    if (!isAuthorized) return;

    setState(() => _isProcessing = true);

    try {
      final physicalStock = double.parse(_physicalStockController.text);
      final currentAdminId = widget.authController.currentUser?.id ?? 'ADMIN_OVERRIDE';

      await _inventoryRepo.adjustStock(
        productoId: widget.product.id,
        stockFisico: physicalStock,
        motivo: _selectedReason!,
        adminId: currentAdminId,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajuste guardado y encolado para sincronización.'), backgroundColor: Color(0xFF2E7D32)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al ajustar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theoretical = widget.product.stockActual;
    final formatDecimals = widget.product.esAGranel ? 3 : 0;

    Color diffColor = Colors.grey.shade700;
    String diffPrefix = '';
    if (_difference > 0) {
      diffColor = const Color(0xFF2E7D32);
      diffPrefix = '+';
    } else if (_difference < 0) {
      diffColor = const Color(0xFFD32F2F);
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.balance, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Ajuste y Merma Físico', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.product.descripcion, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('SKU: ${widget.product.sku ?? "N/A"}', style: const TextStyle(color: Colors.grey)),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Stock Teórico (Sistema):', style: TextStyle(fontSize: 14)),
                  Text(theoretical.toStringAsFixed(formatDecimals), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _physicalStockController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))],
                decoration: const InputDecoration(
                  labelText: 'Stock Físico (Conteo Real) *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory_2),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingrese el conteo real';
                  if (double.tryParse(v) == null) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: diffColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: diffColor.withValues(alpha: 0.5))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Diferencia de Ajuste:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('$diffPrefix${_difference.toStringAsFixed(formatDecimals)}', style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Motivo de Ajuste *', border: OutlineInputBorder()),
                initialValue: _selectedReason,
                items: _motivos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setState(() => _selectedReason = val),
                validator: (v) => v == null ? 'Seleccione un motivo' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
          onPressed: _isProcessing ? null : _handleSave,
          child: _isProcessing 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
            : const Text('Guardar Ajuste'),
        ),
      ],
    );
  }
}