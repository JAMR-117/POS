import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/local/models.dart';
import '../../data/repositories/product_repository.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? productToEdit;
  final ProductRepository repository;

  const ProductFormScreen({
    super.key,
    this.productToEdit,
    required this.repository,
  });

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _codigoController;
  late TextEditingController _descripcionController;
  late TextEditingController _precioCompraController;
  late TextEditingController _precioVentaController;
  late TextEditingController _impuestosController;
  late TextEditingController _departamentoController;
  
  bool _esAGranel = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    _codigoController = TextEditingController(text: p?.codigoBarras ?? '');
    _descripcionController = TextEditingController(text: p?.descripcion ?? '');
    _precioCompraController = TextEditingController(text: p?.precioCompra.toString() ?? '');
    _precioVentaController = TextEditingController(text: p?.precioVenta.toString() ?? '');
    _impuestosController = TextEditingController(text: p?.porcentajeImpuesto.toString() ?? '0.0');
    _departamentoController = TextEditingController(text: p?.departamento ?? 'General');
    _esAGranel = p?.esAGranel ?? false;
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _descripcionController.dispose();
    _precioCompraController.dispose();
    _precioVentaController.dispose();
    _impuestosController.dispose();
    _departamentoController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final product = Product(
        id: widget.productToEdit?.id ?? _generateLocalUUID(),
        codigoBarras: _codigoController.text.trim().isEmpty ? null : _codigoController.text.trim(),
        sku: _codigoController.text.trim().isEmpty ? null : _codigoController.text.trim(),
        descripcion: _descripcionController.text.trim(),
        precioCompra: double.tryParse(_precioCompraController.text) ?? 0.0,
        precioVenta: double.parse(_precioVentaController.text),
        porcentajeImpuesto: double.tryParse(_impuestosController.text) ?? 0.0,
        departamento: _departamentoController.text.trim(),
        stockActual: widget.productToEdit?.stockActual ?? 0.0,
        esAGranel: _esAGranel,
      );

      await widget.repository.saveProduct(product, isUpdate: widget.productToEdit != null);
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productToEdit == null ? 'Nuevo Producto' : 'Editar Producto'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F4E79),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codigoController,
                          decoration: const InputDecoration(
                            labelText: 'Código de Barras / SKU',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.qr_code),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.camera_alt, color: Color(0xFF1F4E79), size: 32),
                        tooltip: 'Escanear código',
                        onPressed: () {
                          // TODO: Implementar lector de cámara nativo
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descripcionController,
                    decoration: const InputDecoration(labelText: 'Descripción *', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'La descripción es obligatoria' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _precioCompraController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Precio de Compra', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _precioVentaController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Precio de Venta *', border: OutlineInputBorder()),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Requerido';
                            if (double.tryParse(v) == null) return 'Precio inválido';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _impuestosController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Impuestos (%)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _departamentoController,
                          decoration: const InputDecoration(labelText: 'Departamento', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    title: const Text('¿Se vende a granel / fraccionado?'),
                    subtitle: const Text('Habilita cantidades decimales en el Punto de Venta (ej. 0.450 kg)'),
                    value: _esAGranel,
                    activeThumbColor: const Color(0xFF1F4E79),
                    onChanged: (bool value) => setState(() => _esAGranel = value),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _handleSave,
                    child: const Text('GUARDAR PRODUCTO'),
                  ),
                ],
              ),
            ),
    );
  }
}