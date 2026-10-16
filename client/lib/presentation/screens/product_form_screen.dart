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
  late TextEditingController _skuController;
  late TextEditingController _nombreController;
  late TextEditingController _descripcionController;
  late TextEditingController _marcaController;
  late TextEditingController _equivalenciaController;
  late TextEditingController _ubicacionController;
  late TextEditingController _precioCompraController;
  late TextEditingController _precioVentaController;
  late TextEditingController _precioCerrajeroController;
  late TextEditingController _precioTallerController;
  late TextEditingController _cantidadMayoreoController;
  late TextEditingController _precioMayoreoController;
  late TextEditingController _stockMinimoController;
  late TextEditingController _impuestosController;
  late TextEditingController _departamentoController;
  late TextEditingController _stockActualController;
  late TextEditingController _cantidadInsumoController;
  
  bool _esAGranel = false;
  bool _esServicio = false;
  String? _insumoVinculadoId;
  List<Product> _insumosDisponibles = [];
  List<String> _departamentosDisponibles = [];
  bool _isLoading = false;

  final List<String> _marcasComunes = [
    'Alba',
    'JMA',
    'Dexter',
    'Ilco',
    'Silca',
    'Phillips',
    'Xhorse',
    'Genérica',
    'Taller',
    'Yale',
    'Tover',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    _codigoController = TextEditingController(text: p?.codigoBarras ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _nombreController = TextEditingController(text: p?.nombre ?? '');
    _descripcionController = TextEditingController(text: p?.descripcion ?? '');
    _marcaController = TextEditingController(text: p?.marca ?? 'Genérica');
    _equivalenciaController = TextEditingController(text: p?.codigoEquivalencia ?? '');
    _ubicacionController = TextEditingController(text: p?.ubicacion ?? '');
    _precioCompraController = TextEditingController(text: p?.precioCompra.toString() ?? '0.0');
    _precioVentaController = TextEditingController(text: p?.precioVenta.toString() ?? '');
    _precioCerrajeroController = TextEditingController(text: p?.precioCerrajero?.toString() ?? '');
    _precioTallerController = TextEditingController(text: p?.precioTaller?.toString() ?? '');
    _cantidadMayoreoController = TextEditingController(text: p?.cantidadMayoreo?.toString() ?? '');
    _precioMayoreoController = TextEditingController(text: p?.precioMayoreo?.toString() ?? '');
    _stockMinimoController = TextEditingController(text: p?.stockMinimo.toString() ?? '5.0');
    _impuestosController = TextEditingController(text: p?.porcentajeImpuesto.toString() ?? '0.16');
    _departamentoController = TextEditingController(text: p?.departamento ?? 'Llaves Tradicionales');
    _stockActualController = TextEditingController(text: p?.stockActual.toString() ?? '0.0');
    _cantidadInsumoController = TextEditingController(text: p?.cantidadInsumo.toString() ?? '1.0');

    _esAGranel = p?.esAGranel ?? false;
    _esServicio = p?.esServicio ?? false;
    _insumoVinculadoId = p?.insumoVinculadoId;

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final physicals = await widget.repository.getPhysicalProducts();
      final deptos = await widget.repository.getDepartmentNames();
      if (mounted) {
        setState(() {
          _insumosDisponibles = physicals;
          _departamentosDisponibles = deptos;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _skuController.dispose();
    _nombreController.dispose();
    _descripcionController.dispose();
    _marcaController.dispose();
    _equivalenciaController.dispose();
    _ubicacionController.dispose();
    _precioCompraController.dispose();
    _precioVentaController.dispose();
    _precioCerrajeroController.dispose();
    _precioTallerController.dispose();
    _cantidadMayoreoController.dispose();
    _precioMayoreoController.dispose();
    _stockMinimoController.dispose();
    _impuestosController.dispose();
    _departamentoController.dispose();
    _stockActualController.dispose();
    _cantidadInsumoController.dispose();
    super.dispose();
  }

  Future<void> _pickLinkedInsumo() async {
    final selected = await showDialog<Product>(
      context: context,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _insumosDisponibles.where((p) {
              if (filter.isEmpty) return true;
              final f = filter.toLowerCase();
              return p.nombre.toLowerCase().contains(f) ||
                  (p.sku ?? '').toLowerCase().contains(f) ||
                  (p.codigoEquivalencia ?? '').toLowerCase().contains(f) ||
                  (p.marca ?? '').toLowerCase().contains(f);
            }).toList();

            return AlertDialog(
              title: const Text('Vincular Insumo Físico (BOM Ligero)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por clave, molde o marca (ej. R-52, PHI-52, TP08)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setModalState(() => filter = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No hay insumos coincidentes.'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final item = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.vpn_key, color: Color(0xFF1F4E79)),
                                  title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('SKU: ${item.sku ?? "-"} | Marca: ${item.marca ?? "-"} | Molde: ${item.codigoEquivalencia ?? "-"}'),
                                  trailing: Text(
                                    'Stock: ${item.stockActual}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: item.stockActual <= 5 ? Colors.red : Colors.green.shade800,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _insumoVinculadoId = selected.id;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    
    try {
      final String id = widget.productToEdit?.id ?? _generateLocalUUID();
      final String nombre = _nombreController.text.trim();
      final String descripcion = _descripcionController.text.trim();
      final String? codigo = _codigoController.text.trim().isEmpty ? null : _codigoController.text.trim();
      final String? sku = _skuController.text.trim().isEmpty ? codigo : _skuController.text.trim();

      final product = Product(
        id: id,
        codigoBarras: codigo,
        sku: sku,
        nombre: nombre,
        descripcion: descripcion,
        marca: _marcaController.text.trim().isEmpty ? 'Genérica' : _marcaController.text.trim(),
        codigoEquivalencia: _equivalenciaController.text.trim().isEmpty ? null : _equivalenciaController.text.trim().toUpperCase(),
        ubicacion: _ubicacionController.text.trim().isEmpty ? null : _ubicacionController.text.trim(),
        precioCompra: double.tryParse(_precioCompraController.text) ?? 0.0,
        precioVenta: double.parse(_precioVentaController.text),
        precioCerrajero: double.tryParse(_precioCerrajeroController.text),
        precioTaller: double.tryParse(_precioTallerController.text),
        stockMinimo: double.tryParse(_stockMinimoController.text) ?? 5.0,
        porcentajeImpuesto: double.tryParse(_impuestosController.text) ?? 0.0,
        departamento: _departamentoController.text.trim().isEmpty ? 'General' : _departamentoController.text.trim(),
        stockActual: _esServicio ? 999.0 : (double.tryParse(_stockActualController.text) ?? 0.0),
        esAGranel: _esAGranel,
        cantidadMayoreo: double.tryParse(_cantidadMayoreoController.text),
        precioMayoreo: double.tryParse(_precioMayoreoController.text),
        esServicio: _esServicio,
        insumoVinculadoId: _esServicio ? _insumoVinculadoId : null,
        cantidadInsumo: _esServicio ? (double.tryParse(_cantidadInsumoController.text) ?? 1.0) : 1.0,
      );

      await widget.repository.saveProduct(product, isUpdate: widget.productToEdit != null);
      
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Producto guardado exitosamente.'), backgroundColor: Colors.green),
        );
        nav.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Product? get _linkedInsumoProduct {
    if (_insumoVinculadoId == null) return null;
    try {
      return _insumosDisponibles.firstWhere((p) => p.id == _insumoVinculadoId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.productToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Producto / Servicio' : 'Nuevo Producto / Servicio'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Guardar',
            onPressed: _isLoading ? null : _handleSave,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Tipo: Servicio vs Físico
                  Card(
                    color: _esServicio ? const Color(0xFFF3E5F5) : const Color(0xFFE8F5E9),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: _esServicio ? Colors.purple.shade300 : Colors.green.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _esServicio ? '⚙️ Es un Servicio (Duplicado, Programación, Corte)' : '📦 Es un Producto Físico (Llave, Cerradura, Transponder)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(_esServicio 
                              ? 'Permite descontar un insumo físico automáticamente de stock por cada servicio realizado.' 
                              : 'Controla existencia física e inventario directo.'),
                            value: _esServicio,
                            activeThumbColor: Colors.purple,
                            onChanged: (val) {
                              setState(() {
                                _esServicio = val;
                                if (_esServicio && _departamentoController.text == 'Llaves Tradicionales') {
                                  _departamentoController.text = 'Servicios';
                                }
                              });
                            },
                          ),
                          if (_esServicio) ...[
                            const Divider(),
                            const Text(
                              'Insumo Físico Vinculado (BOM Ligero):',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                            ),
                            const SizedBox(height: 8),
                            if (_insumoVinculadoId != null && _linkedInsumoProduct != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.purple.shade200),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.vpn_key, color: Colors.purple),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _linkedInsumoProduct!.nombre,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          Text(
                                            'SKU: ${_linkedInsumoProduct!.sku ?? "-"} | Stock: ${_linkedInsumoProduct!.stockActual}',
                                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _pickLinkedInsumo,
                                      icon: const Icon(Icons.swap_horiz, size: 16),
                                      label: const Text('Cambiar'),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                      tooltip: 'Quitar insumo',
                                      onPressed: () => setState(() => _insumoVinculadoId = null),
                                    ),
                                  ],
                                ),
                              )
                            else
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.purple.shade800,
                                  side: BorderSide(color: Colors.purple.shade400),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onPressed: _pickLinkedInsumo,
                                icon: const Icon(Icons.search),
                                label: const Text('Buscar y vincular insumo (Llave virgen, Chip, Carcasa)...'),
                              ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _cantidadInsumoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Cantidad de insumo consumido por cada servicio',
                                isDense: true,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                                suffixText: 'unidades',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Datos Principales
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Comercial / Corto *',
                      hintText: 'Ej. Llave Virgen R-52, Duplicado Llave Tradicional, Chip TP08...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es obligatorio' : null,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _descripcionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción Técnica / Compatibilidad *',
                      hintText: 'Ej. Compatible cerraduras Phillips 715, 5 pernos o Chip Megamos Crypto VW Jetta A4...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'La descripción técnica es obligatoria' : null,
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codigoController,
                          decoration: const InputDecoration(
                            labelText: 'Código de Barras',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.qr_code),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _skuController,
                          decoration: const InputDecoration(
                            labelText: 'Clave / SKU de Llave',
                            hintText: 'Ej. R-52, PHI-52, TP08, DX-1',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Marca y Equivalencia (Cross-Reference)
                  Row(
                    children: [
                      Expanded(
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(text: _marcaController.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return _marcasComunes;
                            return _marcasComunes.where((m) => m.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (val) => _marcaController.text = val,
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Marca / Fabricante',
                                hintText: 'Alba, JMA, Dexter, Ilco, Xhorse...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.business_outlined),
                              ),
                              onChanged: (v) => _marcaController.text = v,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _equivalenciaController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Molde Universal (Equivalencia)',
                            hintText: 'Ej. EQ-PHI52, EQ-DX1',
                            helperText: 'Vincula llaves idénticas entre diferentes marcas',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sync_alt),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Ubicación Física (Exclusiva de pantalla)
                  TextFormField(
                    controller: _ubicacionController,
                    decoration: const InputDecoration(
                      labelText: '📍 Ubicación Física Interna (Solo Operador en Pantalla)',
                      hintText: 'Ej. Tablero 1 - Gancho 14, Gaveta Chips #1, Estante C...',
                      helperText: 'Esta información NUNCA se imprimirá en el ticket del cliente ni en cotizaciones.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin_drop_outlined, color: Color(0xFFD84315)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SISTEMA MULTI-PRECIO (LISTAS POR NIVEL)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.price_change, color: Color(0xFF1F4E79), size: 20),
                            SizedBox(width: 8),
                            Text('Esquema de Precios por Nivel (Multi-Tier Pricing)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _precioCompraController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Costo Unitario Compra (\$)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _precioVentaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Precio 1: Público Casual * (\$)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.monetization_on, color: Color(0xFF2E7D32)),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Requerido';
                                  if (double.tryParse(v) == null) return 'Precio inválido';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _precioCerrajeroController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Precio 2: Colega Cerrajero (\$)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.vpn_key, color: Color(0xFF0D47A1)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _precioTallerController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Precio 3: Taller Automotriz (\$)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.build, color: Color(0xFF4A148C)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _cantidadMayoreoController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Cant. Mínima Mayoreo',
                                  hintText: 'Ej. 10 piezas',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _precioMayoreoController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Precio 4: Mayoreo por Volumen (\$)',
                                  hintText: 'Ej. 10.00',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.layers, color: Color(0xFFE65100)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Departamento, Stock Actual y Stock Mínimo
                  Row(
                    children: [
                      Expanded(
                        child: Autocomplete<String>(
                          initialValue: TextEditingValue(text: _departamentoController.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return _departamentosDisponibles;
                            return _departamentosDisponibles.where((d) => d.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (val) => _departamentoController.text = val,
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Departamento / Familia',
                                hintText: 'Llaves Tradicionales, Electrónica...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                              onChanged: (v) => _departamentoController.text = v,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!_esServicio) ...[
                        Expanded(
                          child: TextFormField(
                            controller: _stockActualController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Stock Físico Actual',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _stockMinimoController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Stock Mínimo (Punto de Reorden)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (!_esServicio)
                    SwitchListTile(
                      title: const Text('¿Se vende a granel / fraccionado?'),
                      subtitle: const Text('Habilita cobro de cantidades con decimales'),
                      value: _esAGranel,
                      activeThumbColor: const Color(0xFF1F4E79),
                      onChanged: (val) => setState(() => _esAGranel = val),
                    ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _handleSave,
                    child: const Text('GUARDAR PRODUCTO / SERVICIO'),
                  ),
                ],
              ),
            ),
    );
  }
}