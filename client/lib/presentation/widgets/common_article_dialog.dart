import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/cart_controller.dart';

class CommonArticleDialog extends StatefulWidget {
  final CartController cartController;

  const CommonArticleDialog({super.key, required this.cartController});

  static Future<void> show(BuildContext context, CartController controller) async {
    await showDialog(
      context: context,
      builder: (_) => CommonArticleDialog(cartController: controller),
    );
  }

  @override
  State<CommonArticleDialog> createState() => _CommonArticleDialogState();
}

class _CommonArticleDialogState extends State<CommonArticleDialog> {
  final TextEditingController _montoController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  void _submit() {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    if (monto > 0) {
      widget.cartController.addCommonArticle(monto, description: _descController.text.trim());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fastfood_outlined, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Artículo Común', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _montoController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'Monto a cobrar (\$)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción (Opcional)',
                hintText: 'Ej. Copias, Servicio, Varios...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
          onPressed: _submit,
          child: const Text('AGREGAR [ENTER]'),
        ),
      ],
    );
  }
}