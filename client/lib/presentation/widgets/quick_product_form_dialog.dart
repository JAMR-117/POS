import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
// Asumiendo que tienes un ProductRepository para aislar la lógica de SQLite
// Si no, puedes usar DatabaseHelper directamente.
import '../../data/repositories/product_repository.dart';

class QuickProductFormDialog extends StatefulWidget {
  final String barcode;
  final ProductRepository productRepository;

  const QuickProductFormDialog({
    super.key, 
    required this.barcode, 
    required this.productRepository,
  });

  static Future<Product?> show(BuildContext context, String barcode, ProductRepository repo) async {
    return showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QuickProductFormDialog(barcode: barcode, productRepository: repo),
    );
  }

  @override
  State<QuickProductFormDialog> createState() => _QuickProductFormDialogState();
}

class _QuickProductFormDialogState extends State<QuickProductFormDialog> {
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _precioVentaController = TextEditingController();
  final TextEditingController _precioCompraController = TextEditingController();
  
  bool _esAGranel = false;
  bool _isProcessing = false;
  String? _error;

  String _generateUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _handleSave() async {
    final descripcion = _descController.text.trim();
    final precioVenta = double.tryParse(_precioVentaController.text) ?? 0.0;
    final precioCompra = double.tryParse(_precioCompraController.text) ?? 0.0;

    if (descripcion.isEmpty || precioVenta <= 0) {
      setState(() => _error = 'La descripción y el precio de venta son obligatorios.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final newProduct = Product(
        id: _generateUUID(),
        codigoBarras: widget.barcode,
        sku: widget.barcode,
        descripcion: descripcion,
        precioCompra: precioCompra,
        precioVenta: precioVenta,
        porcentajeImpuesto: 0.0,
        departamento: 'General',
        stockActual: 0.0, // Inicia en 0, el checkout lo pasará a negativo
        esAGranel: _esAGranel,
        // Campos de mayoreo añadidos en la Iteración 1
        cantidadMayoreo: null,
        precioMayoreo: null,
      );

      // Persistencia local (esto debería guardar en SQLite e insertar en sync_queue)
      await widget.productRepository.saveProduct(newProduct);
      
      if (mounted) {
        Navigator.of(context).pop(newProduct);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error al guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Alta Rápida de Producto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.amber.shade50,
                child: Text('Código escaneado: ${widget.barcode}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13)),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              TextField(
                controller: _descController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción del Producto *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _precioCompraController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      decoration: const InputDecoration(labelText: 'Costo (\$)', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _precioVentaController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(labelText: 'Precio Venta * (\$)', border: OutlineInputBorder()),
                      onSubmitted: (_) => _handleSave(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('¿Se vende a granel / peso?'),
                subtitle: const Text('Permite cobrar cantidades con decimales'),
                value: _esAGranel,
                onChanged: (val) => setState(() => _esAGranel = val),
                activeColor: const Color(0xFF1F4E79),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
          onPressed: _isProcessing ? null : _handleSave,
          child: _isProcessing 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('GUARDAR Y COBRAR'),
        ),
      ],
    );
  }
}