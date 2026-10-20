import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/sales_repository.dart';
import 'quick_product_form_dialog.dart';

/// Modal flotante de búsqueda avanzada [F1] al 85% de pantalla.
/// Búsqueda ágil con atajos de teclado, visualización completa de precios por nivel y moldes.
class AdvancedProductSearchDialog extends StatefulWidget {
  final SalesRepository salesRepository;
  final ProductRepository? productRepository;
  final Function(Product) onProductSelected;
  final String initialQuery;

  const AdvancedProductSearchDialog({
    super.key,
    required this.salesRepository,
    this.productRepository,
    required this.onProductSelected,
    this.initialQuery = '',
  });

  static Future<Product?> show({
    required BuildContext context,
    required SalesRepository salesRepository,
    ProductRepository? productRepository,
    String initialQuery = '',
  }) async {
    return showDialog<Product>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AdvancedProductSearchDialog(
        salesRepository: salesRepository,
        productRepository: productRepository,
        onProductSelected: (p) => Navigator.of(ctx).pop(p),
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<AdvancedProductSearchDialog> createState() => _AdvancedProductSearchDialogState();
}

class _AdvancedProductSearchDialogState extends State<AdvancedProductSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Product> _results = [];
  int _selectedIndex = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _performSearch(widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final q = query.trim();
      List<Product> prods;
      if (q.isEmpty) {
        prods = await widget.salesRepository.searchProductsAdvanced('%', limit: 40);
      } else {
        prods = await widget.salesRepository.searchProductsAdvanced(q, limit: 50);
      }

      if (mounted) {
        setState(() {
          _results = prods;
          _selectedIndex = 0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterByMold(String mold) {
    _searchController.text = 'molde:$mold';
    _performSearch('molde:$mold');
    _searchFocusNode.requestFocus();
  }

  void _selectCurrent() {
    if (_results.isNotEmpty && _selectedIndex >= 0 && _selectedIndex < _results.length) {
      widget.onProductSelected(_results[_selectedIndex]);
    }
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, _results.length - 1);
    });
    // Auto scroll para mantener la fila visible
    if (_scrollController.hasClients) {
      const rowHeight = 48.0;
      final targetOffset = _selectedIndex * rowHeight;
      if (targetOffset < _scrollController.offset ||
          targetOffset > _scrollController.offset + 300) {
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _openQuickEdit() async {
    if (_results.isEmpty || widget.productRepository == null) return;
    final selected = _results[_selectedIndex];
    final updated = await QuickProductFormDialog.show(
      context,
      selected.codigoBarras ?? selected.sku ?? selected.id,
      widget.productRepository!,
    );
    if (updated != null && mounted) {
      _performSearch(_searchController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.85;
    final dialogHeight = screenSize.height * 0.85;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): _selectCurrent,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.f2): _openQuickEdit,
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        insetPadding: const EdgeInsets.all(20.0),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildSearchInput(),
              const SizedBox(height: 12),
              Expanded(child: _buildTableArea()),
              const SizedBox(height: 12),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1F4E79).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.manage_search, color: Color(0xFF1F4E79), size: 28),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buscar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              Text(
                'Búsqueda ágil por SKU, Código de barras, Marca, Nombre, Descripción o Molde',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSearchInput() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      onChanged: (val) => _performSearch(val),
      decoration: InputDecoration(
        hintText: 'Escribe para buscar (ej. R-52, PHI-52, VW, JMA, Phillips, Transponder, Chip)...',
        prefixIcon: const Icon(Icons.search, color: Color(0xFF1F4E79)),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _performSearch('');
                  _searchFocusNode.requestFocus();
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildTableArea() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No se encontraron productos coincidentes con "${_searchController.text}"',
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: Column(
        children: [
          // Header de la tabla
          Container(
            color: const Color(0xFF1F4E79),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Row(
              children: [
                SizedBox(width: 100, child: Text('CLAVE/SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                Expanded(flex: 3, child: Text('DESCRIPCIÓN / PRODUCTO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('MARCA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 130, child: Text('MOLDE (EQ.)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 100, child: Text('UBICACIÓN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 70, child: Text('STOCK', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('PÚBLICO', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 85, child: Text('CERRAJERO', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 80, child: Text('TALLER', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 85, child: Text('MAYOREO', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
          ),
          // Filas de resultados
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: _results.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final p = _results[index];
                final isSelected = index == _selectedIndex;
                final bool isService = p.esServicio;

                final Color stockColor = isService
                    ? Colors.purple
                    : (p.stockActual <= 0
                        ? Colors.red.shade700
                        : (p.stockActual <= p.stockMinimo ? Colors.orange.shade800 : Colors.green.shade800));

                final String stockText = isService
                    ? 'Servicio'
                    : p.stockActual.toStringAsFixed(p.stockActual % 1 != 0 ? 2 : 0);

                return InkWell(
                  onTap: () {
                    setState(() => _selectedIndex = index);
                  },
                  onDoubleTap: () {
                    setState(() => _selectedIndex = index);
                    _selectCurrent();
                  },
                  child: Container(
                    color: isSelected
                        ? const Color(0xFF1F4E79).withValues(alpha: 0.12)
                        : (index.isEven ? Colors.white : const Color(0xFFF9FAFB)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            p.sku ?? p.codigoBarras ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1F4E79)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                              if (p.descripcion.isNotEmpty && p.descripcion != p.nombre)
                                Text(
                                  p.descripcion,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            p.marca ?? '-',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: p.codigoEquivalencia != null && p.codigoEquivalencia!.isNotEmpty
                              ? Tooltip(
                                  message: 'Ver variantes y alternativas de Molde: ${p.codigoEquivalencia}',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _filterByMold(p.codigoEquivalencia!),
                                      borderRadius: BorderRadius.circular(4),
                                      hoverColor: const Color(0xFF1F4E79).withValues(alpha: 0.15),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F2FD),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF1976D2)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.link, size: 12, color: Color(0xFF0D47A1)),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                'Molde: ${p.codigoEquivalencia!}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0D47A1),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : const Text('-', style: TextStyle(color: Colors.grey)),
                        ),
                        SizedBox(
                          width: 100,
                          child: p.ubicacion != null && p.ubicacion!.isNotEmpty
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: Colors.amber.shade400),
                                  ),
                                  child: Text(
                                    '📍 ${p.ubicacion}',
                                    style: TextStyle(fontSize: 11, color: Colors.brown.shade900, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              : const Text('-', style: TextStyle(color: Colors.grey)),
                        ),
                        SizedBox(
                          width: 70,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: stockColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              stockText,
                              style: TextStyle(color: stockColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '\$${p.precioVenta.toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2E7D32)),
                          ),
                        ),
                        SizedBox(
                          width: 85,
                          child: Text(
                            p.precioCerrajero != null ? '\$${p.precioCerrajero!.toStringAsFixed(2)}' : '-',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF0D47A1)),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            p.precioTaller != null ? '\$${p.precioTaller!.toStringAsFixed(2)}' : '-',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF4A148C)),
                          ),
                        ),
                        SizedBox(
                          width: 85,
                          child: Text(
                            p.precioMayoreo != null ? '\$${p.precioMayoreo!.toStringAsFixed(2)}' : '-',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFE65100)),
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

  Widget _buildFooter() {
    return Row(
      children: [
        Wrap(
          spacing: 8,
          children: [
            _buildShortcutBadge('↑ / ↓', 'Navegar'),
            _buildShortcutBadge('Enter', 'Agregar a Ticket'),
            _buildShortcutBadge('F2', 'Editar / Alta Rápida'),
            _buildShortcutBadge('Esc', 'Cerrar'),
          ],
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar [ESC]'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F4E79),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: _results.isNotEmpty ? _selectCurrent : null,
          icon: const Icon(Icons.add_shopping_cart, size: 18),
          label: const Text('Agregar a Ticket [ENTER]', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildShortcutBadge(String key, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black87)),
        ],
      ),
    );
  }
}
