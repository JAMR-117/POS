import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/inventory/inventory_api_client.dart';
import '../../data/local/database_helper.dart';
import '../../data/local/models.dart';
import '../../data/repositories/product_repository.dart';
import '../controllers/auth_controller.dart';
import '../widgets/stock_adjustment_dialog.dart';
import '../widgets/catalog_import_dialog.dart';
import 'product_form_screen.dart';

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

class _InventoryScreenState extends State<InventoryScreen> {
  final ProductRepository _productRepo = ProductRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Product> _products = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  // Estado de Sincronización en Background
  bool _isSyncing = false;
  bool _isOffline = false;
  String? _lastSyncTimestamp;

  String _selectedSort = 'nombre_asc';
  String _selectedDepartamento = 'Todos';
  String _selectedMarca = 'Todas';
  String _selectedTipo = 'todos'; // 'todos', 'fisicos', 'servicios'
  bool _soloBajoStock = false;

  List<String> _departamentos = ['Todos'];
  List<String> _marcas = ['Todas'];

  List<InventoryMovementRecord> _kardexMovements = [];
  bool _isLoadingKardex = false;

  Timer? _debounceTimer;

  final Map<String, String> _sortOptions = const {
    'nombre_asc': 'Nombre (A-Z)',
    'nombre_desc': 'Nombre (Z-A)',
    'stock_asc': 'Menor stock físico',
    'stock_desc': 'Mayor stock físico',
    'precio_asc': 'Menor precio de venta',
    'precio_desc': 'Mayor precio de venta',
    'marca_asc': 'Marca / Fabricante',
  };

  @override
  void initState() {
    super.initState();
    _loadSyncMetadata();
    _loadLocalCatalog();
    _loadKardex();
    _triggerBackgroundSync();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
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
    if (mounted) {
      setState(() {
        _lastSyncTimestamp = meta;
      });
    }
  }

  Future<void> _loadKardex() async {
    setState(() => _isLoadingKardex = true);
    try {
      final movs = await DatabaseHelper.instance.getInventoryMovements(limit: 150);
      if (mounted) setState(() => _kardexMovements = movs);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingKardex = false);
  }

  /// Carga el catálogo 100% desde SQLite local (Latencia Cero y Fuente de Verdad)
  Future<void> _loadLocalCatalog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
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

      // Cargar lista única de departamentos y marcas para los filtros
      final all = await _productRepo.getAllProducts();
      final deptos = {'Todos', ...all.map((p) => p.departamento).where((d) => d.isNotEmpty)};
      final mks = {'Todas', ...all.map((p) => p.marca ?? 'Genérica').where((m) => m.isNotEmpty)};

      if (!mounted) return;

      setState(() {
        _products = filteredItems;
        _departamentos = deptos.toList();
        _marcas = mks.toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al leer la base de datos local: $e';
        _isLoading = false;
      });
    }
  }

  /// Sincronización en segundo plano con Fallback Transparente
  Future<void> _triggerBackgroundSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      // Intenta conectar con el backend
      await widget.apiClient.fetchVelocityCatalog(limit: 5, tiendaId: widget.tiendaId);

      // Si respondió con éxito:
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
      // Si falla o no hay conexión de red, pasamos transparente a modo offline sin bloquear pantalla
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

  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'Nunca';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFECEFF1),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F4E79),
          foregroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 22),
              SizedBox(width: 8),
              Text('Catálogo e Inventario de Cerrajería', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFFB74D),
            indicatorWeight: 3,
            onTap: (idx) {
              if (idx == 1) _loadKardex();
            },
            tabs: const [
              Tab(icon: Icon(Icons.inventory_2), text: 'Catálogo de Productos'),
              Tab(icon: Icon(Icons.history_edu), text: 'Kardex de Movimientos'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recargar catálogo local y sincronizar',
              onPressed: () {
                _loadLocalCatalog();
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
              label: const Text('NUEVO PRODUCTO / SERVICIO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(repository: _productRepo),
                  ),
                );
                if (created == true) {
                  _loadLocalCatalog();
                }
              },
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                _buildSyncStatusBanner(),
                _buildFilterBar(),
                Expanded(
                  child: _buildTableContainer(),
                ),
                _buildFooterMetrics(),
              ],
            ),
            _buildKardexView(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BANNER DE ESTADO DE SINCRONIZACIÓN (OFFLINE-FIRST)
  // ---------------------------------------------------------------------------
  Widget _buildSyncStatusBanner() {
    if (_isSyncing) {
      return Container(
        color: Colors.blue.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: const Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1F4E79))),
            SizedBox(width: 10),
            Text('Comprobando enlace de sincronización con el servidor backend...', style: TextStyle(fontSize: 12, color: Color(0xFF1F4E79))),
          ],
        ),
      );
    }

    if (_isOffline) {
      return Container(
        color: Colors.amber.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: Color(0xFFD84315), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ Modo Offline / Sin conexión con el servidor — Mostrando inventario local (SQLite). Última actualización exitosa: ${_formatTimestamp(_lastSyncTimestamp)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFBF360C)),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFBF360C),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Reintentar enlace', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _triggerBackgroundSync,
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.green.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '✓ En línea — Catálogo local sincronizado con el backend central. Última actualización: ${_formatTimestamp(_lastSyncTimestamp)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BARRA DE BÚSQUEDA Y FILTROS LOCALES
  // ---------------------------------------------------------------------------
  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Column(
        children: [
          Row(
            children: [
              // Barra de búsqueda con soporte para %
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por Clave, Nombre, Marca o con % (ej. %jetta a4, %phillips)...',
                    prefixIcon: Icon(Icons.search, size: 20, color: Color(0xFF1F4E79)),
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF9FAFB),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Selector de Ordenación
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedSort,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Ordenar por',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFFF9FAFB),
                  ),
                  items: _sortOptions.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null && val != _selectedSort) {
                      setState(() => _selectedSort = val);
                      _loadLocalCatalog();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 1050;

              final tipoSelector = SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'todos', label: Text('Todos', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'fisicos', label: Text('📦 Físicos', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'servicios', label: Text('⚙️ Servicios', style: TextStyle(fontSize: 12))),
                ],
                selected: {_selectedTipo},
                onSelectionChanged: (newVal) {
                  setState(() => _selectedTipo = newVal.first);
                  _loadLocalCatalog();
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              );

              final deptoDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedDepartamento,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Familia / Departamento',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF9FAFB),
                ),
                items: _departamentos
                    .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDepartamento = val);
                    _loadLocalCatalog();
                  }
                },
              );

              final marcaDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedMarca,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Marca / Fabricante',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF9FAFB),
                ),
                items: _marcas
                    .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedMarca = val);
                    _loadLocalCatalog();
                  }
                },
              );

              final bajoStockChip = FilterChip(
                avatar: const Icon(Icons.warning_amber, size: 16, color: Color(0xFFE65100)),
                label: const Text('Bajo Mínimo (Escasez)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                selected: _soloBajoStock,
                selectedColor: const Color(0xFFFFE0B2),
                onSelected: (val) {
                  setState(() => _soloBajoStock = val);
                  _loadLocalCatalog();
                },
              );

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        tipoSelector,
                        const SizedBox(width: 12),
                        bajoStockChip,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: deptoDropdown),
                        const SizedBox(width: 12),
                        Expanded(child: marcaDropdown),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  tipoSelector,
                  const SizedBox(width: 12),
                  Expanded(child: deptoDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: marcaDropdown),
                  const SizedBox(width: 12),
                  bajoStockChip,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLA VISUAL DE PRODUCTOS, MOLDES, UBICACIÓN Y BOM
  // ---------------------------------------------------------------------------
  Widget _buildTableContainer() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadLocalCatalog, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No se encontraron productos o servicios que coincidan con los filtros.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCFD8DC)),
      ),
      child: Column(
        children: [
          // Header de la Tabla
          Container(
            color: const Color(0xFF1F4E79),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('PRODUCTO / SERVICIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 1, child: Text('MARCA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 1, child: Text('EQUIVALENCIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 2, child: Text('📍 UBICACIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                SizedBox(width: 90, child: Text('STOCK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                SizedBox(width: 90, child: Text('P. VENTA', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                SizedBox(width: 100, child: Text('MAYOREO', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                SizedBox(width: 110, child: Text('ACCIONES', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            ),
          ),

          // Lista de Filas
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _products.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
              itemBuilder: (context, idx) {
                final prod = _products[idx];
                final isService = prod.esServicio;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // Producto / Servicio
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    prod.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                if (isService)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: Colors.purple.shade200),
                                    ),
                                    child: const Text('⚙️ Servicio', style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              prod.descripcion,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                            if (prod.sku != null && prod.sku!.isNotEmpty)
                              Text('Clave: ${prod.sku} | Código: ${prod.codigoBarras ?? "N/A"}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                            if (isService && prod.insumoVinculadoId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  '↳ Insumo vinculado: ${prod.insumoVinculadoId} (${prod.cantidadInsumo} pza/serv)',
                                  style: TextStyle(fontSize: 10, color: Colors.purple.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Marca
                      Expanded(
                        flex: 1,
                        child: Text(
                          prod.marca ?? 'Genérica',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF37474F)),
                        ),
                      ),

                      // Equivalencia (Molde Universal) Clickeable
                      Expanded(
                        flex: 1,
                        child: prod.codigoEquivalencia != null && prod.codigoEquivalencia!.isNotEmpty
                            ? Tooltip(
                                message: 'Clic para filtrar todas las llaves del Molde: ${prod.codigoEquivalencia}',
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _filterByMolde(prod.codigoEquivalencia!),
                                    borderRadius: BorderRadius.circular(4),
                                    hoverColor: Colors.blue.shade100,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blue.shade400),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.link, size: 12, color: Color(0xFF0D47A1)),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              prod.codigoEquivalencia!,
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const Text('-', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),

                      // Ubicación Física
                      Expanded(
                        flex: 2,
                        child: prod.ubicacion != null && prod.ubicacion!.isNotEmpty
                            ? Row(
                                children: [
                                  const Text('📍 ', style: TextStyle(fontSize: 11)),
                                  Expanded(
                                    child: Text(
                                      prod.ubicacion!,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD84315)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              )
                            : const Text('Sin asignar', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),

                      // Stock
                      SizedBox(
                        width: 90,
                        child: Center(
                          child: isService
                              ? const Text('Ilimitado', style: TextStyle(fontSize: 11, color: Colors.black54))
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: prod.stockActual <= 0
                                        ? Colors.red.shade100
                                        : (prod.stockActual <= 5 ? Colors.amber.shade100 : Colors.green.shade100),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    prod.stockActual.toStringAsFixed(prod.esAGranel ? 3 : 0),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: prod.stockActual <= 0
                                          ? Colors.red.shade900
                                          : (prod.stockActual <= 5 ? Colors.amber.shade900 : Colors.green.shade900),
                                    ),
                                  ),
                                ),
                        ),
                      ),

                      // Precio Venta
                      SizedBox(
                        width: 90,
                        child: Text(
                          '\$${prod.precioVenta.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E7D32)),
                        ),
                      ),

                      // Precio Mayoreo
                      SizedBox(
                        width: 100,
                        child: prod.hasWholesalePrice
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${prod.precioMayoreo!.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1F4E79)),
                                  ),
                                  Text('≥ ${prod.cantidadMayoreo!.toStringAsFixed(0)} pzas', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                ],
                              )
                            : const Text('-', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),

                      // Acciones
                      SizedBox(
                        width: 110,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Ajuste de Stock (Solo físicos)
                            if (!isService && prod.id != 'ART-COMUN')
                              IconButton(
                                icon: const Icon(Icons.tune, size: 18, color: Color(0xFF1F4E79)),
                                tooltip: 'Ajuste de Stock Físico',
                                onPressed: () async {
                                  final adjusted = await StockAdjustmentDialog.show(context, prod, widget.authController);
                                  if (adjusted) {
                                    _loadLocalCatalog();
                                  }
                                },
                              )
                            else
                              const SizedBox(width: 40),

                            // Editar Producto
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF546E7A)),
                              tooltip: 'Editar Producto / Servicio',
                              onPressed: () async {
                                final edited = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => ProductFormScreen(
                                      repository: _productRepo,
                                      productToEdit: prod,
                                    ),
                                  ),
                                );
                                if (edited == true) {
                                  _loadLocalCatalog();
                                }
                              },
                            ),
                          ],
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

  // ---------------------------------------------------------------------------
  // BARRA INFERIOR DE MÉTRICAS DEL CATÁLOGO
  // ---------------------------------------------------------------------------
  Widget _buildFooterMetrics() {
    final totalCount = _products.length;
    final totalServicios = _products.where((p) => p.esServicio).length;
    final totalFisicos = totalCount - totalServicios;
    final sinStock = _products.where((p) => !p.esServicio && p.stockActual <= 0).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Text('Total Mostrados: $totalCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 16),
          Text('Físicos: $totalFisicos', style: const TextStyle(fontSize: 12, color: Colors.black87)),
          const SizedBox(width: 16),
          Text('Servicios: $totalServicios', style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          if (sinStock > 0)
            Text('⚠️ Sin Existencia: $sinStock', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
          const Spacer(),
          const Text('Base de datos SQLite local activa (pos_local.db)', style: TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VISTA DE KARDEX / HISTORIAL DE MOVIMIENTOS
  // ---------------------------------------------------------------------------
  Widget _buildKardexView() {
    if (_isLoadingKardex) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_kardexMovements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.history, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No hay movimientos registrados en el Kardex local.', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadKardex, child: const Text('Recargar Movimientos')),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFF1F4E79),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: const Row(
              children: [
                SizedBox(width: 125, child: Text('FECHA / HORA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 115, child: Text('TIPO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('PRODUCTO / INSUMO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 100, child: Text('DEPTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 70, child: Text('CANT.', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 115, child: Text('STOCK (ANT -> NVO)', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('USUARIO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 2, child: Text('MOTIVO / REFERENCIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _kardexMovements.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final m = _kardexMovements[index];
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
                  case 'CANCELACION':
                    badgeColor = Colors.red.shade700;
                    break;
                  default:
                    badgeColor = Colors.grey.shade700;
                }

                final dateStr = DateFormat('dd/MM/yy HH:mm').format(m.fecha.toLocal());
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: index.isEven ? Colors.white : const Color(0xFFF9FAFB),
                  child: Row(
                    children: [
                      SizedBox(width: 125, child: Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.black87))),
                      SizedBox(
                        width: 115,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: badgeColor),
                            ),
                            child: Text(
                              m.tipo,
                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(m.productoDesc, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: 100, child: Text(m.departamento ?? '-', style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                      SizedBox(
                        width: 70,
                        child: Text(
                          m.cantidad.toStringAsFixed(m.cantidad % 1 != 0 ? 2 : 0),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 115,
                        child: Text(
                          '${m.stockAnterior.toStringAsFixed(0)} -> ${m.stockNuevo.toStringAsFixed(0)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                      SizedBox(width: 80, child: Text(m.usuarioId, style: const TextStyle(fontSize: 11, color: Colors.black87), overflow: TextOverflow.ellipsis)),
                      Expanded(
                        flex: 2,
                        child: Text(m.motivo ?? '-', style: const TextStyle(fontSize: 11, color: Colors.black54), overflow: TextOverflow.ellipsis),
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
}