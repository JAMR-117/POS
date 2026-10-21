import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/inventory/inventory_api_client.dart';
import '../../data/local/database_helper.dart';
import '../../data/local/models.dart';
import '../../data/repositories/product_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../widgets/catalog_import_dialog.dart';
import 'product_form_screen.dart';

class ReceptionItem {
  final Product product;
  double quantity;
  double unitCost;
  double? newSalePrice;

  ReceptionItem({
    required this.product,
    required this.quantity,
    required this.unitCost,
    this.newSalePrice,
  });
}

class InventoryScreen extends StatefulWidget {
  final InventoryApiClient apiClient;
  final AuthController authController;
  final String? tiendaId;

  const InventoryScreen({
    super.key,
    required this.apiClient,
    required this.authController,
    this.tiendaId,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ProductRepository _productRepo = ProductRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Product> _products = [];
  List<Product> _allProductsCache = [];
  Product? _selectedProduct; // Inspector lateral master-detail
  bool _isLoading = false;
  String? _errorMessage;

  // Estado de Sincronización en Background
  bool _isSyncing = false;
  bool _isOffline = false;
  String? _lastSyncTimestamp;

  // Filtros del Catálogo
  String _selectedSort = 'nombre_asc';
  String _selectedDepartamento = 'Todos';
  String _selectedMarca = 'Todas';
  String _selectedTipo = 'todos'; // 'todos', 'fisicos', 'servicios'
  bool _soloBajoStock = false;

  List<String> _departamentos = ['Todos'];
  List<String> _marcas = ['Todas'];
  List<String> _locations = ['Todas'];

  // Pestaña 2: Recepción de Mercancía / Compras
  final List<ReceptionItem> _receptionList = [];
  final TextEditingController _receptionSearchCtrl = TextEditingController();
  bool _isProcessingReceipt = false;

  // Pestaña 3: Conteo Físico / Auditoría por Gaveta
  String _auditLocationFilter = 'Todas';
  String _auditDeptoFilter = 'Todos';
  final Map<String, double> _physicalCounts = {};
  bool _isApplyingAudit = false;

  // Pestaña 4: Kardex
  List<InventoryMovementRecord> _kardexMovements = [];
  bool _isLoadingKardex = false;
  String _kardexTypeFilter = 'Todos';
  final TextEditingController _kardexSearchCtrl = TextEditingController();

  Timer? _debounceTimer;

  final Map<String, String> _sortOptions = const {
    'nombre_asc': 'Nombre (A-Z)',
    'nombre_desc': 'Nombre (Z-A)',
    'stock_asc': 'Menor stock físico',
    'stock_desc': 'Mayor stock físico',
    'precio_asc': 'Menor precio público',
    'precio_desc': 'Mayor precio público',
    'marca_asc': 'Marca / Fabricante',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 3) {
        _loadKardex();
      }
    });

    _loadSyncMetadata();
    _loadLocalCatalog();
    _loadLocations();
    _loadKardex();
    _triggerBackgroundSync();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _receptionSearchCtrl.dispose();
    _kardexSearchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await _productRepo.getDistinctLocations();
      if (mounted) {
        setState(() => _locations = ['Todas', ...locs]);
      }
    } catch (_) {}
  }

  void _filterByMolde(String molde) {
    setState(() {
      _selectedDepartamento = 'Todos';
      _selectedMarca = 'Todas';
      _selectedTipo = 'todos';
      _soloBajoStock = false;
      _searchController.text = 'molde:$molde';
    });
    _loadLocalCatalog();
  }

  Future<void> _loadSyncMetadata() async {
    final meta = await DatabaseHelper.instance.getMetadata('last_inventory_sync_at');
    if (mounted) setState(() => _lastSyncTimestamp = meta);
  }

  Future<void> _loadKardex() async {
    setState(() => _isLoadingKardex = true);
    try {
      final movs = await DatabaseHelper.instance.getInventoryMovements(limit: 200);
      if (mounted) setState(() => _kardexMovements = movs);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingKardex = false);
  }

  /// Carga el catálogo 100% desde SQLite local (Latencia Cero)
  Future<void> _loadLocalCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final all = await _productRepo.getAllProducts();
      final items = await _productRepo.searchProducts(
        query: _searchController.text,
        departamento: _selectedDepartamento == 'Todos' ? null : _selectedDepartamento,
        marca: _selectedMarca == 'Todas' ? null : _selectedMarca,
        soloServicios: _selectedTipo == 'servicios' ? true : null,
        soloFisicos: _selectedTipo == 'fisicos' ? true : null,
        sortBy: _selectedSort,
      );

      final filteredItems = _soloBajoStock
          ? items.where((p) => !p.esServicio && p.stockActual <= p.stockMinimo).toList()
          : items;

      final deptos = <String>{'Todos', ...all.map((p) => p.departamento).where((d) => d.isNotEmpty)};
      final mks = <String>{'Todas', ...all.map((p) => (p.marca != null && p.marca!.isNotEmpty) ? p.marca! : 'Genérica')};

      if (!mounted) return;

      setState(() {
        _allProductsCache = all;
        _products = filteredItems;
        _departamentos = deptos.toList();
        _marcas = mks.toList();
        _isLoading = false;

        // Mantener sincronizado el producto seleccionado en el inspector
        if (_selectedProduct != null) {
          final idx = all.indexWhere((p) => p.id == _selectedProduct!.id);
          if (idx != -1) {
            _selectedProduct = all[idx];
          } else {
            _selectedProduct = null;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al leer la base de datos local: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerBackgroundSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await widget.apiClient.fetchVelocityCatalog(limit: 5, tiendaId: widget.tiendaId);
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await DatabaseHelper.instance.setMetadata('last_inventory_sync_at', nowIso);

      if (mounted) {
        setState(() {
          _isOffline = false;
          _lastSyncTimestamp = nowIso;
          _isSyncing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isOffline = true;
          _isSyncing = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _loadLocalCatalog();
    });
  }

  String _formatTimestamp(dynamic val) {
    if (val == null) return 'Nunca';
    if (val is DateTime) {
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(val.toLocal());
    }
    final iso = val.toString();
    if (iso.isEmpty) return 'Nunca';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
    } catch (_) {
      return iso;
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFAZ PRINCIPAL
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, size: 22),
            SizedBox(width: 8),
            Text('Gestión Profesional de Inventario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: const Color(0xFFFFB74D),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2), text: 'Catálogo Maestro'),
            Tab(icon: Icon(Icons.local_shipping), text: 'Recepción de Mercancía'),
            Tab(icon: Icon(Icons.checklist_rtl), text: 'Auditoría por Gaveta'),
            Tab(icon: Icon(Icons.history_edu), text: 'Kardex de Movimientos'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar catálogo local y sincronizar',
            onPressed: () {
              _loadLocalCatalog();
              _loadLocations();
              _loadKardex();
              _triggerBackgroundSync();
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Importar Catálogo Masivo (CSV)',
            onPressed: () async {
              CatalogImportDialog.show(context);
              _loadLocalCatalog();
              _loadLocations();
            },
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('NUEVO ARTÍCULO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final created = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(repository: _productRepo),
                ),
              );
              if (created == true) {
                _loadLocalCatalog();
                _loadLocations();
              }
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Pestaña 1: Catálogo Maestro con Master-Detail
          _buildCatalogMasterTab(),

          // Pestaña 2: Recepción de Mercancía / Compras
          _buildGoodsReceiptTab(),

          // Pestaña 3: Conteo Físico / Auditoría por Gaveta
          _buildAuditByDrawerTab(),

          // Pestaña 4: Kardex / Historial de Movimientos
          _buildKardexView(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 1: CATÁLOGO MAESTRO (CON INSPECTOR MASTER-DETAIL)
  // ---------------------------------------------------------------------------
  Widget _buildCatalogMasterTab() {
    return Column(
      children: [
        _buildSyncStatusBanner(),
        _buildFilterBar(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tabla Principal Despejada
              Expanded(
                child: _buildCleanCatalogTable(),
              ),

              // Inspector Lateral Derecho (360px)
              if (_selectedProduct != null)
                _buildProductInspectorPanel(_selectedProduct!),
            ],
          ),
        ),
        _buildFooterMetrics(),
      ],
    );
  }

  Widget _buildCleanCatalogTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadLocalCatalog, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No se encontraron productos coincidentes.', style: TextStyle(fontSize: 15, color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedDepartamento = 'Todos';
                  _selectedMarca = 'Todas';
                  _selectedTipo = 'todos';
                  _soloBajoStock = false;
                });
                _loadLocalCatalog();
              },
              child: const Text('Limpiar Filtros'),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCFD8DC)),
      ),
      child: Column(
        children: [
          // Cabecera Limpia de la Tabla
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1F4E79),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 140, child: Text('CLAVE / SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('PRODUCTO / SERVICIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('MOLDE', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 100, child: Text('UBICACIÓN', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 110, child: Text('P. PÚBLICO', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 115, child: Text('EXISTENCIA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),

          // Filas de Datos
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _products.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final prod = _products[index];
                final isSelected = _selectedProduct?.id == prod.id;
                final isService = prod.esServicio;

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedProduct?.id == prod.id) {
                        _selectedProduct = null;
                      } else {
                        _selectedProduct = prod;
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: isSelected ? const Color(0xFFE3F2FD) : (index % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA)),
                    child: Row(
                      children: [
                        // 1. Clave / SKU y Marca
                        SizedBox(
                          width: 140,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prod.sku != null && prod.sku!.isNotEmpty ? prod.sku! : (prod.codigoBarras ?? 'S/C'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (prod.marca != null && prod.marca!.isNotEmpty)
                                Text(
                                  prod.marca!,
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),

                        // 2. Nombre del Producto / Servicio
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              if (isService) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.purple.shade200),
                                  ),
                                  child: const Text('SERVICIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple)),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  prod.nombre.isNotEmpty ? prod.nombre : prod.descripcion,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. Molde Raíz (Chip clickeable)
                        SizedBox(
                          width: 90,
                          child: Center(
                            child: (prod.codigoEquivalencia != null && prod.codigoEquivalencia!.isNotEmpty)
                                ? InkWell(
                                    onTap: () => _filterByMolde(prod.codigoEquivalencia!),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade300),
                                      ),
                                      child: Text(
                                        '🔗 ${prod.codigoEquivalencia}',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                      ),
                                    ),
                                  )
                                : const Text('-', style: TextStyle(color: Colors.black38)),
                          ),
                        ),

                        // 4. Ubicación / Gaveta
                        SizedBox(
                          width: 100,
                          child: Center(
                            child: (prod.ubicacion != null && prod.ubicacion!.isNotEmpty)
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3E0),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.orange.shade300),
                                    ),
                                    child: Text(
                                      '📍 ${prod.ubicacion}',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                                    ),
                                  )
                                : const Text('-', style: TextStyle(color: Colors.black38)),
                          ),
                        ),

                        // 5. Precio Público
                        SizedBox(
                          width: 110,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${prod.precioVenta.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E7D32)),
                              ),
                              if (prod.precioCerrajero != null || prod.precioTaller != null)
                                Text(
                                  'Multinivel activo',
                                  style: TextStyle(fontSize: 9, color: Colors.blue.shade700),
                                ),
                            ],
                          ),
                        ),

                        // 6. Existencia con Semáforo
                        SizedBox(
                          width: 115,
                          child: Center(
                            child: isService
                                ? const Text('Ilimitado', style: TextStyle(fontSize: 11, color: Colors.black54))
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: prod.stockActual <= 0
                                          ? const Color(0xFFFFEBEE)
                                          : (prod.stockActual <= prod.stockMinimo ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9)),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: prod.stockActual <= 0
                                            ? Colors.red.shade300
                                            : (prod.stockActual <= prod.stockMinimo ? Colors.orange.shade300 : Colors.green.shade300),
                                      ),
                                    ),
                                    child: Text(
                                      '${prod.stockActual.toStringAsFixed(prod.esAGranel ? 2 : 0)} pzs',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: prod.stockActual <= 0
                                            ? Colors.red.shade800
                                            : (prod.stockActual <= prod.stockMinimo ? Colors.orange.shade900 : Colors.green.shade800),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PANEL INSPECTOR LATERAL DERECHO (MASTER-DETAIL ERP STYLE)
  // ---------------------------------------------------------------------------
  Widget _buildProductInspectorPanel(Product p) {
    final double marginPct = p.precioVenta > 0
        ? (((p.precioVenta - p.precioCompra) / p.precioVenta) * 100)
        : 0.0;

    return Container(
      width: 360,
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCFD8DC)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(-2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado del Inspector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF263238),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Inspector de Producto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                InkWell(
                  onTap: () => setState(() => _selectedProduct = null),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),

          // Cuerpo de Detalles
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // Título y Clave
                Text(
                  p.nombre.isNotEmpty ? p.nombre : p.descripcion,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU: ${p.sku ?? "S/N"}  |  Código: ${p.codigoBarras ?? "S/N"}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),

                // Badges de Ubicación / Molde / Marca
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (p.ubicacion != null && p.ubicacion!.isNotEmpty)
                      _buildChip('📍 Gaveta: ${p.ubicacion}', Colors.orange.shade800, Colors.orange.shade50),
                    if (p.codigoEquivalencia != null && p.codigoEquivalencia!.isNotEmpty)
                      _buildChip('🔗 Molde: ${p.codigoEquivalencia}', Colors.blue.shade800, Colors.blue.shade50),
                    _buildChip('🏷️ Marca: ${(p.marca != null && p.marca!.isNotEmpty) ? p.marca! : "Genérica"}', Colors.grey.shade800, Colors.grey.shade100),
                    _buildChip('📂 ${p.departamento}', const Color(0xFF1F4E79), Colors.blueGrey.shade50),
                  ],
                ),
                const Divider(height: 24),

                // Descripción técnica completa
                const Text('DESCRIPCIÓN Y COMPATIBILIDAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  p.descripcion.isNotEmpty ? p.descripcion : 'Sin descripción técnica adicional.',
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
                const Divider(height: 24),

                // Desglose de Precios y Margen de Rentabilidad
                const Text('NIVELES DE PRECIO Y RENTABILIDAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildPriceRow('Costo de Compra:', '\$${p.precioCompra.toStringAsFixed(2)}', Colors.black87),
                      const SizedBox(height: 4),
                      _buildPriceRow('Precio Público:', '\$${p.precioVenta.toStringAsFixed(2)}', const Color(0xFF2E7D32), isBold: true),
                      const SizedBox(height: 4),
                      _buildPriceRow('Precio Cerrajero:', p.precioCerrajero != null ? '\$${p.precioCerrajero!.toStringAsFixed(2)}' : 'No asignado', Colors.blue.shade800),
                      const SizedBox(height: 4),
                      _buildPriceRow('Precio Taller:', p.precioTaller != null ? '\$${p.precioTaller!.toStringAsFixed(2)}' : 'No asignado', Colors.purple.shade800),
                      if (p.precioMayoreo != null) ...[
                        const SizedBox(height: 4),
                        _buildPriceRow('Mayoreo (+${p.cantidadMayoreo?.toStringAsFixed(0)}):', '\$${p.precioMayoreo!.toStringAsFixed(2)}', Colors.orange.shade900),
                      ],
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Margen de Ganancia:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            '${marginPct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: marginPct >= 30 ? const Color(0xFF2E7D32) : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Si es un servicio con insumo vinculado
                if (p.esServicio && p.insumoVinculadoId != null) ...[
                  const Divider(height: 24),
                  const Text('INSUMO FÍSICO VINCULADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade200)),
                    child: Text(
                      'Descuenta ${p.cantidadInsumo.toStringAsFixed(0)} pz del insumo #${p.insumoVinculadoId!.substring(0, 8)} por cada duplicado.',
                      style: TextStyle(fontSize: 11, color: Colors.purple.shade900),
                    ),
                  ),
                ],

                const Divider(height: 24),
                // Botones de Acción Directa
                const Text('ACCIONES DIRECTAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),

                // 1. Editar Producto
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar Datos del Producto'),
                  onPressed: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => ProductFormScreen(repository: _productRepo, productToEdit: p),
                      ),
                    );
                    if (updated == true) {
                      _loadLocalCatalog();
                    }
                  },
                ),
                const SizedBox(height: 6),

                // 2. Entrada Rápida de Stock
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                  icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF2E7D32)),
                  label: const Text('➕ Entrada Rápida de Stock'),
                  onPressed: () => _openQuickStockEntryDialog(p),
                ),
                const SizedBox(height: 6),

                // 3. Ajustar Stock Manual
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
                  icon: const Icon(Icons.tune, size: 16, color: Color(0xFF1F4E79)),
                  label: const Text('⚖️ Ajustar Stock / Merma'),
                  onPressed: () async {
                    final adjusted = await StockAdjustmentDialog.show(context, p, widget.authController);
                    if (adjusted == true) {
                      _loadLocalCatalog();
                      _loadKardex();
                    }
                  },
                ),
                const SizedBox(height: 6),

                // 4. Eliminar Producto
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                  label: const Text('Eliminar del Catálogo'),
                  onPressed: () => _confirmDeleteProduct(p),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _buildPriceRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color)),
      ],
    );
  }

  Future<void> _openQuickStockEntryDialog(Product p) async {
    final qtyCtrl = TextEditingController(text: '10');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entrada Rápida: ${p.nombre.isNotEmpty ? p.nombre : p.descripcion}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock actual en sistema: ${p.stockActual.toStringAsFixed(0)} piezas'),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cantidad a ingresar (+)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agregar a Inventario', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final double qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
      if (qty > 0) {
        await _productRepo.quickStockEntry(
          p.id,
          qty,
          usuarioId: widget.authController.currentUser?.nombre ?? 'cajero',
        );
        _loadLocalCatalog();
        _loadKardex();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Se agregaron $qty piezas a ${p.sku ?? p.nombre}'), backgroundColor: const Color(0xFF2E7D32)),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteProduct(Product p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Producto?'),
        content: Text('Esta acción eliminará "${p.nombre.isNotEmpty ? p.nombre : p.descripcion}" del catálogo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _productRepo.deleteProduct(p.id);
      setState(() => _selectedProduct = null);
      _loadLocalCatalog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado del catálogo.')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 2: RECEPCIÓN DE MERCANCÍA / COMPRAS RÁPIDAS
  // ---------------------------------------------------------------------------
  Widget _buildGoodsReceiptTab() {
    double totalCompra = _receptionList.fold(0.0, (acc, item) => acc + (item.quantity * item.unitCost));
    double totalPiezas = _receptionList.fold(0.0, (acc, item) => acc + item.quantity);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de Búsqueda y Agregar Artículos a la Recepción
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Autocomplete<Product>(
                      displayStringForOption: (p) => '${p.sku ?? p.id} - ${p.nombre.isNotEmpty ? p.nombre : p.descripcion}',
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) return const Iterable<Product>.empty();
                        final q = textEditingValue.text.toLowerCase();
                        return _allProductsCache.where((p) =>
                            p.nombre.toLowerCase().contains(q) ||
                            p.descripcion.toLowerCase().contains(q) ||
                            (p.sku?.toLowerCase().contains(q) ?? false) ||
                            (p.codigoBarras?.toLowerCase().contains(q) ?? false));
                      },
                      onSelected: (Product selected) {
                        final idx = _receptionList.indexWhere((r) => r.product.id == selected.id);
                        setState(() {
                          if (idx != -1) {
                            _receptionList[idx].quantity += 10.0;
                          } else {
                            _receptionList.add(ReceptionItem(
                              product: selected,
                              quantity: 10.0,
                              unitCost: selected.precioCompra,
                              newSalePrice: selected.precioVenta,
                            ));
                          }
                        });
                      },
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Buscar producto por Nombre, SKU o Código para agregar al pedido...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tabla de Partidas Recibidas
          Expanded(
            child: _receptionList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 54, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No hay partidas en la lista de recepción.',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Usa el buscador superior para agregar productos de tu pedido de proveedor (JMA, Alba, etc.).',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Card(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F4E79),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 130, child: Text('CLAVE / SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 3, child: Text('PRODUCTO RECIBIDO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 120, child: Text('CANTIDAD', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 120, child: Text('COSTO COMPRA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 120, child: Text('SUBTOTAL', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                              SizedBox(width: 50),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _receptionList.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, idx) {
                              final it = _receptionList[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 130,
                                      child: Text(it.product.sku ?? it.product.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(it.product.nombre.isNotEmpty ? it.product.nombre : it.product.descripcion, style: const TextStyle(fontSize: 13)),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Center(
                                        child: SizedBox(
                                          width: 90,
                                          height: 36,
                                          child: TextField(
                                            textAlign: TextAlign.center,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
                                            controller: TextEditingController(text: it.quantity.toStringAsFixed(0)),
                                            onSubmitted: (val) {
                                              final d = double.tryParse(val) ?? it.quantity;
                                              setState(() => it.quantity = d);
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Center(
                                        child: SizedBox(
                                          width: 90,
                                          height: 36,
                                          child: TextField(
                                            textAlign: TextAlign.center,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.zero, prefixText: '\$'),
                                            controller: TextEditingController(text: it.unitCost.toStringAsFixed(2)),
                                            onSubmitted: (val) {
                                              final c = double.tryParse(val) ?? it.unitCost;
                                              setState(() => it.unitCost = c);
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        '\$${(it.quantity * it.unitCost).toStringAsFixed(2)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 50,
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        onPressed: () => setState(() => _receptionList.removeAt(idx)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // Barra de Totales y Confirmación
          if (_receptionList.isNotEmpty)
            Card(
              color: Colors.white,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text('Partidas: ${_receptionList.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(width: 24),
                        Text('Piezas Totales: ${totalPiezas.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79))),
                        const SizedBox(width: 24),
                        Text('Total Factura: \$${totalCompra.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32))),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      icon: _isProcessingReceipt
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: const Text('Confirmar Entrada de Mercancía', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      onPressed: _isProcessingReceipt ? null : _confirmGoodsReceipt,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmGoodsReceipt() async {
    if (_receptionList.isEmpty) return;

    setState(() => _isProcessingReceipt = true);
    try {
      final itemsToProcess = _receptionList.map((r) => {
        'producto_id': r.product.id,
        'cantidad': r.quantity,
        'precio_compra': r.unitCost,
        'precio_venta': r.newSalePrice,
      }).toList();

      await _productRepo.recordGoodsReceipt(
        itemsToProcess,
        usuarioId: widget.authController.currentUser?.nombre ?? 'cajero',
      );

      setState(() {
        _receptionList.clear();
      });
      _loadLocalCatalog();
      _loadKardex();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entrada de mercancía registrada exitosamente en almacén.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error registrando entrada: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingReceipt = false);
    }
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 3: CONTEO FÍSICO / AUDITORÍA POR GAVETA
  // ---------------------------------------------------------------------------
  Widget _buildAuditByDrawerTab() {
    final auditFilteredProducts = _allProductsCache.where((p) {
      if (p.esServicio) return false;
      if (_auditLocationFilter != 'Todas' && (p.ubicacion == null || p.ubicacion != _auditLocationFilter)) return false;
      if (_auditDeptoFilter != 'Todos' && p.departamento != _auditDeptoFilter) return false;
      return true;
    }).toList();

    int discrepancyCount = 0;
    for (final p in auditFilteredProducts) {
      final real = _physicalCounts[p.id] ?? p.stockActual;
      if (real != p.stockActual) discrepancyCount++;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barra de Filtros de Auditoría
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF1F4E79), size: 20),
                  const SizedBox(width: 8),
                  const Text('Filtrar por Gaveta / Tablero: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _locations.contains(_auditLocationFilter) ? _auditLocationFilter : 'Todas',
                    items: _locations.map((loc) => DropdownMenuItem(value: loc, child: Text(loc))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _auditLocationFilter = val);
                    },
                  ),
                  const SizedBox(width: 24),
                  const Text('Departamento: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _departamentos.contains(_auditDeptoFilter) ? _auditDeptoFilter : 'Todos',
                    items: _departamentos.map((dep) => DropdownMenuItem(value: dep, child: Text(dep))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _auditDeptoFilter = val);
                    },
                  ),
                  const Spacer(),
                  Text(
                    'Artículos en esta gaveta: ${auditFilteredProducts.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tabla de Auditoría
          Expanded(
            child: Card(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1F4E79),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 140, child: Text('CLAVE / SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        Expanded(flex: 3, child: Text('PRODUCTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 110, child: Text('UBICACIÓN', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 120, child: Text('STOCK SISTEMA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 140, child: Text('CONTEO FÍSICO REAL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 110, child: Text('DIFERENCIA', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: auditFilteredProducts.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, idx) {
                        final p = auditFilteredProducts[idx];
                        final double realCount = _physicalCounts[p.id] ?? p.stockActual;
                        final double diff = realCount - p.stockActual;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 140, child: Text(p.sku ?? p.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 3, child: Text(p.nombre.isNotEmpty ? p.nombre : p.descripcion, style: const TextStyle(fontSize: 13))),
                              SizedBox(
                                width: 110,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                                    child: Text(p.ubicacion ?? 'Sin Ubicación', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Text('${p.stockActual.toStringAsFixed(0)} pzs', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              SizedBox(
                                width: 140,
                                child: Center(
                                  child: SizedBox(
                                    width: 100,
                                    height: 36,
                                    child: TextField(
                                      textAlign: TextAlign.center,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
                                      controller: TextEditingController(text: realCount.toStringAsFixed(0)),
                                      onSubmitted: (val) {
                                        final parsed = double.tryParse(val) ?? p.stockActual;
                                        setState(() => _physicalCounts[p.id] = parsed);
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 110,
                                child: Center(
                                  child: diff == 0
                                      ? const Text('0', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                                      : Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: diff > 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            diff > 0 ? '+${diff.toStringAsFixed(0)}' : diff.toStringAsFixed(0),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: diff > 0 ? const Color(0xFF2E7D32) : Colors.red.shade800,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Barra de Acción de Auditoría
          Card(
            color: Colors.white,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discrepancias encontradas: $discrepancyCount artículos',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: discrepancyCount > 0 ? Colors.orange.shade900 : const Color(0xFF2E7D32),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: discrepancyCount > 0 ? const Color(0xFF1F4E79) : Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    icon: _isApplyingAudit
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.tune, color: Colors.white),
                    label: const Text('Aplicar Ajustes de Auditoría', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: (_isApplyingAudit || discrepancyCount == 0)
                        ? null
                        : () => _confirmApplyAudit(auditFilteredProducts),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmApplyAudit(List<Product> products) async {
    final List<Map<String, dynamic>> adjustments = [];
    for (final p in products) {
      final real = _physicalCounts[p.id] ?? p.stockActual;
      if (real != p.stockActual) {
        adjustments.add({
          'producto_id': p.id,
          'conteo_fisico': real,
          'motivo': 'Ajuste por conteo físico en gaveta (${p.ubicacion ?? "Sin Ubicación"})',
        });
      }
    }

    if (adjustments.isEmpty) return;

    setState(() => _isApplyingAudit = true);
    try {
      final adjusted = await _productRepo.applyAuditAdjustments(
        adjustments,
        usuarioId: widget.authController.currentUser?.nombre ?? 'cajero',
      );

      setState(() {
        _physicalCounts.clear();
      });
      _loadLocalCatalog();
      _loadKardex();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se cuadraron $adjusted artículos con éxito en inventario.'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error aplicando auditoría: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingAudit = false);
    }
  }

  // ---------------------------------------------------------------------------
  // PESTAÑA 4: KARDEX / HISTORIAL DE MOVIMIENTOS
  // ---------------------------------------------------------------------------
  Widget _buildKardexView() {
    if (_isLoadingKardex) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _kardexSearchCtrl.text.toLowerCase().trim();
    final filtered = _kardexMovements.where((m) {
      if (_kardexTypeFilter != 'Todos' && m.tipo != _kardexTypeFilter) return false;
      if (query.isNotEmpty) {
        final matchesDesc = m.productoDesc.toLowerCase().contains(query);
        final matchesUser = m.usuarioId.toLowerCase().contains(query);
        final matchesReason = m.motivo?.toLowerCase().contains(query) ?? false;
        if (!matchesDesc && !matchesUser && !matchesReason) return false;
      }
      return true;
    }).toList();

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Barra de Filtros del Kardex
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _kardexSearchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar en movimientos (producto, usuario, referencia)...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 14),
                DropdownButton<String>(
                  value: _kardexTypeFilter,
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todos los Tipos')),
                    DropdownMenuItem(value: 'VENTA', child: Text('Ventas')),
                    DropdownMenuItem(value: 'ENTRADA', child: Text('Entradas / Compras')),
                    DropdownMenuItem(value: 'AJUSTE', child: Text('Ajustes Manuales')),
                    DropdownMenuItem(value: 'DEVOLUCION', child: Text('Devoluciones')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _kardexTypeFilter = val);
                  },
                ),
                const SizedBox(width: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79)),
                  icon: const Icon(Icons.download, size: 16, color: Colors.white),
                  label: const Text('Exportar a CSV', style: TextStyle(color: Colors.white)),
                  onPressed: () => _exportKardexToCSV(filtered),
                ),
              ],
            ),
          ),

          // Cabecera de la Tabla Kardex
          Container(
            color: const Color(0xFF1F4E79),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: const Row(
              children: [
                SizedBox(width: 135, child: Text('FECHA / HORA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 110, child: Text('TIPO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('PRODUCTO / INSUMO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 90, child: Text('DEPTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('CANT.', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 120, child: Text('STOCK (ANT -> NVO)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('USUARIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('MOTIVO / REFERENCIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),

          // Lista de Movimientos
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No hay movimientos que coincidan con los filtros.'))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final m = filtered[index];
                      Color badgeColor;
                      switch (m.tipo) {
                        case 'VENTA':
                          badgeColor = Colors.blue.shade700;
                          break;
                        case 'VENTA_SERVICIO':
                          badgeColor = Colors.purple.shade700;
                          break;
                        case 'ENTRADA':
                          badgeColor = Colors.green.shade700;
                          break;
                        case 'AJUSTE':
                          badgeColor = Colors.orange.shade800;
                          break;
                        case 'DEVOLUCION':
                          badgeColor = Colors.teal.shade700;
                          break;
                        default:
                          badgeColor = Colors.grey.shade700;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 135,
                              child: Text(
                                _formatTimestamp(m.fecha),
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                    m.tipo,
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                m.productoDesc,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                m.departamento ?? 'General',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                m.cantidad.toStringAsFixed(m.cantidad % 1 != 0 ? 2 : 0),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: m.tipo == 'ENTRADA' ? const Color(0xFF2E7D32) : Colors.black87,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Text(
                                '${m.stockAnterior.toStringAsFixed(0)} -> ${m.stockNuevo.toStringAsFixed(0)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(m.usuarioId, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                m.motivo ?? '-',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _exportKardexToCSV(List<InventoryMovementRecord> records) {
    final sb = StringBuffer();
    sb.writeln('ID,Fecha,Tipo,Producto,Cantidad,StockAnterior,StockNuevo,Usuario,Motivo');
    for (final r in records) {
      sb.writeln('"${r.id}","${r.fecha}","${r.tipo}","${r.productoDesc}",${r.cantidad},${r.stockAnterior},${r.stockNuevo},"${r.usuarioId}","${r.motivo ?? ""}"');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se exportaron ${records.length} movimientos. Copiado al portapapeles.'),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BARRAS DE FILTRO Y FOOTER DEL CATÁLOGO MAESTRO
  // ---------------------------------------------------------------------------
  Widget _buildSyncStatusBanner() {
    if (!_isOffline && !_isSyncing) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: _isOffline ? const Color(0xFFFFF3E0) : const Color(0xFFE3F2FD),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            _isOffline ? Icons.cloud_off : Icons.sync,
            size: 16,
            color: _isOffline ? Colors.orange.shade800 : Colors.blue.shade800,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOffline
                  ? 'Modo Local Offline: Los cambios se guardan en el dispositivo y se sincronizarán al conectar.'
                  : 'Sincronizando catálogo con el servidor backend...',
              style: TextStyle(
                fontSize: 12,
                color: _isOffline ? Colors.orange.shade900 : Colors.blue.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1050;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: isCompact
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildSearchTextField()),
                        const SizedBox(width: 8),
                        _buildStockAlertFilter(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildDepartmentFilter()),
                        const SizedBox(width: 8),
                        Expanded(child: _buildBrandFilter()),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSortFilter()),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 3, child: _buildSearchTextField()),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _buildDepartmentFilter()),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _buildBrandFilter()),
                    const SizedBox(width: 10),
                    _buildStockAlertFilter(),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: _buildSortFilter()),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSearchTextField() {
    return TextField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, SKU, marca o molde...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                  _loadLocalCatalog();
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    return DropdownButtonFormField<String>(
      initialValue: _departamentos.contains(_selectedDepartamento) ? _selectedDepartamento : 'Todos',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Departamento', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      items: _departamentos.map((dep) => DropdownMenuItem(value: dep, child: Text(dep, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedDepartamento = val);
          _loadLocalCatalog();
        }
      },
    );
  }

  Widget _buildBrandFilter() {
    return DropdownButtonFormField<String>(
      initialValue: _marcas.contains(_selectedMarca) ? _selectedMarca : 'Todas',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      items: _marcas.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedMarca = val);
          _loadLocalCatalog();
        }
      },
    );
  }

  Widget _buildSortFilter() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSort,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Ordenar por', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      items: _sortOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedSort = val);
          _loadLocalCatalog();
        }
      },
    );
  }

  Widget _buildStockAlertFilter() {
    return FilterChip(
      label: const Text('Bajo Stock', style: TextStyle(fontSize: 12)),
      selected: _soloBajoStock,
      selectedColor: const Color(0xFFFFCC80),
      onSelected: (val) {
        setState(() => _soloBajoStock = val);
        _loadLocalCatalog();
      },
    );
  }

  Widget _buildFooterMetrics() {
    final int totalProds = _products.length;
    final int bajoStockCount = _products.where((p) => !p.esServicio && p.stockActual <= p.stockMinimo).length;
    final double totalPiezas = _products.fold(0.0, (acc, p) => acc + (p.esServicio ? 0.0 : p.stockActual));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text('Artículos: $totalProds', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 16),
              Text('Piezas en Almacén: ${totalPiezas.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, color: Color(0xFF1F4E79), fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              if (bajoStockCount > 0)
                Text('⚠️ Bajo Mínimo: $bajoStockCount', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
            ],
          ),
          Text(
            'Última sinc: ${_formatTimestamp(_lastSyncTimestamp)}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
