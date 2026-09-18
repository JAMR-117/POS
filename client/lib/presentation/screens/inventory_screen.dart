import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/inventory/inventory_api_client.dart';

enum VelocityTier {
  alta,
  media,
  baja;

  static VelocityTier fromDaily(double dailyVelocity) {
    if (dailyVelocity >= 3.0) return VelocityTier.alta;
    if (dailyVelocity >= 0.8) return VelocityTier.media;
    return VelocityTier.baja;
  }
}

class InventoryScreen extends StatefulWidget {
  final InventoryApiClient apiClient;
  final String? tiendaId;

  const InventoryScreen({
    super.key,
    required this.apiClient,
    this.tiendaId,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  static const int _pageSize = 40;
  List<VelocityCatalogItem> _catalog = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  int _currentOffset = 0;

  String _selectedSort = 'sales_desc';
  Timer? _debounceTimer;

  final Map<String, String> _sortOptions = const {
    'sales_desc': 'Más vendidos (30d)',
    'total_sold_desc': 'Mayor salida total',
    'stock_asc': 'Menor stock',
    'stock_desc': 'Mayor stock',
    'sales_asc': 'Menor venta',
  };

  @override
  void initState() {
    super.initState();
    _fetchCatalog(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchCatalog(reset: false);
    }
  }

  Future<void> _fetchCatalog({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentOffset = 0;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final items = await widget.apiClient.fetchVelocityCatalog(
        sort: _selectedSort,
        limit: _pageSize,
        offset: reset ? 0 : _currentOffset,
        tiendaId: widget.tiendaId,
      );

      if (!mounted) return; // <- Protege contra desmontaje

      setState(() {
        if (reset) {
          _catalog = items;
        } else {
          _catalog.addAll(items);
        }
        _currentOffset += items.length;
        if (items.length < _pageSize) {
          _hasMore = false;
        }
      });
    } catch (e) {
      if (!mounted) return; // <- Protege contra desmontaje
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) { // <- Solo actualiza estado si la pantalla sigue abierta
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      setState(() {});
    });
  }

  List<VelocityCatalogItem> get _filteredCatalog {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _catalog;
    return _catalog.where((item) {
      final desc = item.descripcion.toLowerCase();
      final sku = (item.sku ?? '').toLowerCase();
      final barcode = (item.codigoBarras ?? '').toLowerCase();
      return desc.contains(query) || sku.contains(query) || barcode.contains(query);
    }).toList();
  }

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
            Text('Catálogo e Inventario Dinámico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar catálogo',
            onPressed: () => _fetchCatalog(reset: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _buildTableContainer(),
          ),
          _buildFooterMetrics(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Filtrar en vista activa por descripción, SKU o barras...',
                prefixIcon: Icon(Icons.search, size: 20, color: Color(0xFF1F4E79)),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF9FAFB),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedSort,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Criterio de ordenación',
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
                  _fetchCatalog(reset: true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableContainer() {
    if (_isLoading && _catalog.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _catalog.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 10),
            Text(_errorMessage!, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => _fetchCatalog(reset: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final items = _filteredCatalog;

    if (items.isEmpty) {
      return const Center(
        child: Text('No se hallaron productos con el filtro aplicado.', style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCFD8DC)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: items.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return _buildTableRow(items[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFF263238),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: const Row(
        children: [
          SizedBox(width: 90, child: Text('ROTACIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          SizedBox(width: 140, child: Text('CÓDIGO / SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(flex: 3, child: Text('DESCRIPCIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(flex: 2, child: Text('DEPTO.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          SizedBox(width: 90, child: Text('STOCK', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          SizedBox(width: 90, child: Text('30D VENTAS', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          SizedBox(width: 90, child: Text('SALIDA/DÍA', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          SizedBox(width: 90, child: Text('RUNWAY', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildTableRow(VelocityCatalogItem item) {
    final bool isGranel = (item.stockActual % 1 != 0);
    final String stockFormat = item.stockActual.toStringAsFixed(isGranel ? 3 : 0);
    final tier = VelocityTier.fromDaily(item.velocidadDiaria);

    Color tierColor;
    String tierLabel;
    switch (tier) {
      case VelocityTier.alta:
        tierColor = const Color(0xFF2E7D32);
        tierLabel = 'ALTA';
        break;
      case VelocityTier.media:
        tierColor = const Color(0xFF0288D1);
        tierLabel = 'MEDIA';
        break;
      case VelocityTier.baja:
        tierColor = const Color(0xFF757575);
        tierLabel = 'BAJA';
        break;
    }

    final String runwayText = item.diasRestantes >= 9999 ? '∞' : '${item.diasRestantes.toStringAsFixed(1)} d';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      color: Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Row(
              children: [
                Container(width: 4, height: 22, color: tierColor),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(tierLabel, style: TextStyle(color: tierColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              item.codigoBarras ?? item.sku ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(item.descripcion, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 2,
            child: Text(item.departamento, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          SizedBox(
            width: 90,
            child: Text(
              stockFormat,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: item.stockActual <= 0 ? const Color(0xFFD32F2F) : Colors.black87,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              item.ventasUltimos30Dias.toStringAsFixed(isGranel ? 1 : 0),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              item.velocidadDiaria.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              runwayText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: item.diasRestantes <= 7.0 && item.stockActual > 0 ? const Color(0xFFE65100) : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterMetrics() {
    return Container(
      color: const Color(0xFFECEFF1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Artículos cargados: ${_catalog.length}${_hasMore ? '+' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const Row(
            children: [
              Text('Alta (>=3.0/d)  |  Media (>=0.8/d)  |  Baja (<0.8/d)', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ],
          ),
        ],
      ),
    );
  }
}