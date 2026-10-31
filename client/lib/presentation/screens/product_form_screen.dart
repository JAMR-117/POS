import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/department_theme.dart';
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

  bool _esAGranel = false;
  bool _esServicio = false;
  bool _aplicaATodos = true;
  final Set<String> _departamentosSeleccionados = {};

  List<String> _departamentosDisponibles = [...kAllStandardDepartments];
  bool _isLoading = false;

  final List<String> _marcasComunes = [
    'Alba',
    'JMA',
    'Dexter',
    'Ilco',
    'Silca',
    'Phillips',
    'Xhorse',
    'KEYDIY',
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
    _impuestosController = TextEditingController(text: p?.porcentajeImpuesto.toString() ?? '0.0');
    _departamentoController = TextEditingController(text: p?.departamento ?? 'Residencial');
    _stockActualController = TextEditingController(text: p?.stockActual.toString() ?? '0.0');

    _esAGranel = p?.esAGranel ?? false;
    _esServicio = p?.esServicio ?? false;

    if (p != null && p.esServicio) {
      final list = p.departamentosAplicablesList;
      if (list.isEmpty || list.any((d) => d.toLowerCase() == 'todos')) {
        _aplicaATodos = true;
        _departamentosSeleccionados.clear();
      } else {
        _aplicaATodos = false;
        _departamentosSeleccionados.addAll(list);
      }
    }

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final deptos = await widget.repository.getDepartmentNames();
      if (mounted && deptos.isNotEmpty) {
        setState(() {
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
    super.dispose();
  }

  String _computeDepartamentosAplicables() {
    if (!_esServicio) return 'Todos';
    if (_aplicaATodos || _departamentosSeleccionados.isEmpty) {
      return 'Todos';
    }
    return _departamentosSeleccionados.join(',');
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (_esServicio && !_aplicaATodos && _departamentosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un departamento aplicable o marca "Todos".'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      final String? codigo = _codigoController.text.trim().isEmpty ? null : _codigoController.text.trim();
      final String? sku = _skuController.text.trim().isEmpty ? codigo : _skuController.text.trim();
      final String id = widget.productToEdit?.id ?? (sku ?? codigo ?? _generateLocalUUID());
      final String nombre = _nombreController.text.trim();
      final String descripcion = _descripcionController.text.trim().isEmpty
          ? nombre
          : _descripcionController.text.trim();

      final String deptoFinal = _esServicio
          ? 'Servicios'
          : (_departamentoController.text.trim().isEmpty ? 'Residencial' : _departamentoController.text.trim());

      final product = Product(
        id: id,
        codigoBarras: codigo ?? id,
        sku: sku ?? id,
        nombre: nombre,
        descripcion: descripcion,
        marca: _esServicio
            ? (_marcaController.text.trim().isEmpty ? 'Taller' : _marcaController.text.trim())
            : (_marcaController.text.trim().isEmpty ? 'Genérica' : _marcaController.text.trim()),
        codigoEquivalencia: _esServicio || _equivalenciaController.text.trim().isEmpty
            ? null
            : _equivalenciaController.text.trim().toUpperCase(),
        ubicacion: _esServicio || _ubicacionController.text.trim().isEmpty
            ? null
            : _ubicacionController.text.trim(),
        precioCompra: _esServicio ? 0.0 : (double.tryParse(_precioCompraController.text) ?? 0.0),
        precioVenta: double.parse(_precioVentaController.text),
        precioCerrajero: double.tryParse(_precioCerrajeroController.text),
        precioTaller: double.tryParse(_precioTallerController.text),
        stockMinimo: _esServicio ? 0.0 : (double.tryParse(_stockMinimoController.text) ?? 5.0),
        porcentajeImpuesto: double.tryParse(_impuestosController.text) ?? 0.0,
        departamento: deptoFinal,
        departamentosAplicables: _computeDepartamentosAplicables(),
        stockActual: _esServicio ? 999.0 : (double.tryParse(_stockActualController.text) ?? 0.0),
        esAGranel: _esServicio ? false : _esAGranel,
        cantidadMayoreo: double.tryParse(_cantidadMayoreoController.text),
        precioMayoreo: double.tryParse(_precioMayoreoController.text),
        esServicio: _esServicio,
        insumoVinculadoId: null, // Dynamic Runtime BOM en caja reemplaza vínculo fijo
        cantidadInsumo: 1.0,
      );

      await widget.repository.saveProduct(product, isUpdate: widget.productToEdit != null);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(_esServicio ? 'Servicio maestro guardado exitosamente.' : 'Producto guardado exitosamente.'),
            backgroundColor: Colors.green,
          ),
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

  List<String> get _selectableServiceDepartments {
    final base = <String>[...kPhysicalDepartments];
    for (final d in _departamentosDisponibles) {
      if (d != 'Servicios' && d != 'Todos' && !base.contains(d)) {
        base.add(d);
      }
    }
    return base;
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
                  // 1. Switch Principal: ¿Es un Servicio? vs Producto Físico
                  Card(
                    color: _esServicio ? const Color(0xFFE0F7FA) : const Color(0xFFE8F5E9),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: _esServicio ? Colors.cyan.shade400 : Colors.green.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _esServicio
                                  ? '🛠️ ¿Es un Servicio? (Activado: Servicio Configurable por Departamento)'
                                  : '📦 ¿Es un Servicio? (Desactivado: Producto Físico con Inventario)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: Text(
                              _esServicio
                                  ? 'El insumo físico (llave, chip o carcasa) se vinculará y descontará dinámicamente al momento de cobrar en caja.'
                                  : 'Controla existencias en gaveta, molde equivalente y alertas de reorden.',
                            ),
                            value: _esServicio,
                            activeThumbColor: Colors.cyan.shade800,
                            onChanged: (val) {
                              setState(() {
                                _esServicio = val;
                                if (_esServicio) {
                                  _departamentoController.text = 'Servicios';
                                  if (_marcaController.text == 'Genérica') {
                                    _marcaController.text = 'Taller';
                                  }
                                } else if (_departamentoController.text == 'Servicios') {
                                  _departamentoController.text = 'Residencial';
                                }
                              });
                            },
                          ),

                          // Selector Múltiple de Departamentos Aplicables (Solo Servicios)
                          if (_esServicio) ...[
                            const Divider(height: 20),
                            Row(
                              children: [
                                Icon(Icons.account_tree_outlined, size: 18, color: Colors.cyan.shade900),
                                const SizedBox(width: 8),
                                Text(
                                  '¿Para qué departamentos aplica este servicio?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.cyan.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Al elegir en caja un producto físico de estos departamentos, el sistema ofrecerá aplicar este servicio.',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.cyan.shade200),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilterChip(
                                    label: const Text('Todos los Departamentos'),
                                    selected: _aplicaATodos,
                                    selectedColor: Colors.cyan.shade100,
                                    checkmarkColor: Colors.cyan.shade900,
                                    labelStyle: TextStyle(
                                      fontWeight: _aplicaATodos ? FontWeight.bold : FontWeight.normal,
                                      color: _aplicaATodos ? Colors.cyan.shade900 : Colors.black87,
                                    ),
                                    onSelected: (selected) {
                                      setState(() {
                                        _aplicaATodos = selected;
                                        if (selected) {
                                          _departamentosSeleccionados.clear();
                                        }
                                      });
                                    },
                                  ),
                                  ..._selectableServiceDepartments.map((dep) {
                                    final isSelected = !_aplicaATodos && _departamentosSeleccionados.contains(dep);
                                    final style = DepartmentStyle.of(dep);
                                    return FilterChip(
                                      avatar: Icon(style.icon, size: 15, color: style.fg),
                                      label: Text(dep),
                                      selected: isSelected,
                                      selectedColor: style.bg,
                                      checkmarkColor: style.fg,
                                      side: BorderSide(color: isSelected ? style.fg : Colors.grey.shade300),
                                      labelStyle: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? style.fg : Colors.black87,
                                      ),
                                      onSelected: (selected) {
                                        setState(() {
                                          if (selected) {
                                            _aplicaATodos = false;
                                            _departamentosSeleccionados.add(dep);
                                          } else {
                                            _departamentosSeleccionados.remove(dep);
                                            if (_departamentosSeleccionados.isEmpty) {
                                              _aplicaATodos = true;
                                            }
                                          }
                                        });
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Datos Principales
                  TextFormField(
                    controller: _nombreController,
                    decoration: InputDecoration(
                      labelText: _esServicio ? 'Nombre del Servicio *' : 'Nombre Comercial / Corto *',
                      hintText: _esServicio
                          ? 'Ej. Duplicado de Llave Residencial, Programación de Transponder...'
                          : 'Ej. Llave Virgen R-52, Chip TP08, Control Keydiy...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.title),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es obligatorio' : null,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _descripcionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _esServicio ? 'Descripción del Servicio' : 'Descripción Técnica / Compatibilidad *',
                      hintText: _esServicio
                          ? 'Ej. Incluye corte de llave y ajuste básico en mostrador'
                          : 'Ej. Compatible cerraduras Phillips 715, 5 pernos o Chip Megamos Crypto VW Jetta A4...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.description_outlined),
                    ),
                    validator: (v) {
                      if (!_esServicio && (v == null || v.trim().isEmpty)) {
                        return 'La descripción técnica es obligatoria';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codigoController,
                          decoration: InputDecoration(
                            labelText: _esServicio ? 'Código Interno del Servicio' : 'Código de Barras',
                            hintText: _esServicio ? 'Ej. SRV-DUP-RES' : null,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.qr_code),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _skuController,
                          decoration: InputDecoration(
                            labelText: _esServicio ? 'Clave Corta (SKU)' : 'Clave / SKU de Llave',
                            hintText: _esServicio ? 'Ej. SRV-DUP-RES' : 'Ej. R-52, PHI-52, TP08, DX-1',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Marca, Molde y Ubicación solo para Productos Físicos
                  if (!_esServicio) ...[
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
                              hintText: 'Ej. R52, R52L, PHI-14D, A89',
                              helperText: 'Vincula llaves equivalentes entre distintas marcas',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.sync_alt),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _ubicacionController,
                      decoration: const InputDecoration(
                        labelText: '📍 Ubicación Física Interna (Solo Operador en Pantalla)',
                        hintText: 'Ej. RE-14, AU-08, SE-12, MO-04, Vitrina Chips...',
                        helperText: 'Esta información NUNCA se imprimirá en el ticket del cliente ni en cotizaciones.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pin_drop_outlined, color: Color(0xFFD84315)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. SISTEMA MULTI-PRECIO (PRECIOS SUGERIDOS DEL SERVICIO O PRODUCTO)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.price_change, color: Color(0xFF1F4E79), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _esServicio
                                  ? 'Precios Sugeridos del Servicio por Categoría (Editables en Caja)'
                                  : 'Esquema de Precios por Nivel (Multi-Tier Pricing)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (!_esServicio) ...[
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
                            ],
                            Expanded(
                              child: TextFormField(
                                controller: _precioVentaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: _esServicio
                                      ? 'Precio Público Sugerido (Precio 1) * (\$)'
                                      : 'Precio 1: Público Casual * (\$)',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.monetization_on, color: Color(0xFF2E7D32)),
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
                                  labelText: 'Precio Cerrajero / Gremio (Precio 2) (\$)',
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
                                  labelText: 'Precio Taller Automotriz (Precio 3) (\$)',
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
                                controller: _precioMayoreoController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Precio Mayoreo (Precio 4) (\$)',
                                  hintText: 'Ej. 15.00',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.layers, color: Color(0xFFE65100)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _cantidadMayoreoController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Cant. Mínima Mayoreo (Opcional)',
                                  hintText: 'Ej. 5 piezas / servicios',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Departamento, Stock Actual y Stock Mínimo (Solo Productos Físicos)
                  if (!_esServicio) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: kPhysicalDepartments.contains(_departamentoController.text)
                                ? _departamentoController.text
                                : 'Residencial',
                            decoration: const InputDecoration(
                              labelText: 'Departamento Estandarizado *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _selectableServiceDepartments
                                .map((dep) => DropdownMenuItem(value: dep, child: Text(dep)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _departamentoController.text = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
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
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      title: const Text('¿Se vende a granel / fraccionado?'),
                      subtitle: const Text('Habilita cobro de cantidades con decimales'),
                      value: _esAGranel,
                      activeThumbColor: const Color(0xFF1F4E79),
                      onChanged: (val) => setState(() => _esAGranel = val),
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _handleSave,
                    label: Text(_esServicio ? 'GUARDAR SERVICIO CONFIGURABLE' : 'GUARDAR PRODUCTO FÍSICO'),
                  ),
                ],
              ),
            ),
    );
  }
}
