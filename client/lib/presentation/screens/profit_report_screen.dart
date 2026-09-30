import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/repositories/reports_repository.dart';
import '../controllers/auth_controller.dart';

class ProfitReportScreen extends StatefulWidget {
  final AuthController authController;

  const ProfitReportScreen({super.key, required this.authController});

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen> {
  final ReportsRepository _reportsRepo = ReportsRepository();
  
  ProfitReportSummary? _report;
  bool _isLoading = true;
  String? _error;
  
  late DateTime _startDate;
  late DateTime _endDate;
  String _activeFilter = 'Hoy';

  @override
  void initState() {
    super.initState();
    _setFilter('Hoy');
  }

  void _setFilter(String filter) {
    setState(() {
      _activeFilter = filter;
      final now = DateTime.now();
      if (filter == 'Hoy') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'Esta Semana') {
        _startDate = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (filter == 'Este Mes') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _loadReport();
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF1F4E79)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _activeFilter = 'Personalizado';
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadReport();
    }
  }

  Future<void> _loadReport() async {
    if (!widget.authController.isAdmin) return; // Capa extra de seguridad silenciosa

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await _reportsRepo.getGrossProfitReport(_startDate, _endDate);
      if (mounted) setState(() => _report = summary);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // RBAC: Bloqueo Estricto Visual
    if (!widget.authController.isAdmin) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 80, color: Colors.red),
              SizedBox(height: 16),
              Text('Acceso Denegado', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('Esta sección es exclusiva para el Administrador.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECEFF1),
      appBar: AppBar(
        title: const Text('Reporte de Utilidades y Rentabilidad'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadReport),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
                    : _buildReportContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.date_range, color: Color(0xFF1F4E79)),
          const SizedBox(width: 16),
          _filterButton('Hoy'),
          _filterButton('Esta Semana'),
          _filterButton('Este Mes'),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.edit_calendar),
            label: Text(
              _activeFilter == 'Personalizado' 
                ? '${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}'
                : 'Rango Personalizado',
            ),
            onPressed: _selectCustomRange,
          )
        ],
      ),
    );
  }

  Widget _filterButton(String label) {
    final isActive = _activeFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isActive,
        selectedColor: const Color(0xFF1F4E79).withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isActive ? const Color(0xFF1F4E79) : Colors.black87,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => _setFilter(label),
      ),
    );
  }

  Widget _buildReportContent() {
    if (_report == null) return const SizedBox();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _buildKPICard('Ventas Netas', _report!.totalVentas, Icons.point_of_sale, Colors.blue)),
            Expanded(child: _buildKPICard('Costo de Mercancía (COGS)', _report!.cogs, Icons.inventory, Colors.orange)),
            Expanded(
              child: _buildKPICard(
                'Ganancia Bruta', 
                _report!.gananciaBruta, 
                Icons.trending_up, 
                const Color(0xFF2E7D32),
                subtitle: 'Margen: ${_report!.margenPorcentual.toStringAsFixed(1)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Top 10: Artículos Más Rentables', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
            columns: const [
              DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Unidades Vendidas', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
              DataColumn(label: Text('Utilidad Generada', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            ],
            rows: _report!.topProductos.map((prod) => DataRow(
              cells: [
                DataCell(Text(prod.descripcion, style: const TextStyle(fontWeight: FontWeight.w500))),
                DataCell(Text(prod.cantidadVendida.toStringAsFixed(2))),
                DataCell(Text('\$${prod.utilidadGenerada.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold))),
              ],
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, double amount, IconData icon, Color color, {String? subtitle}) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Text('\$${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
            ]
          ],
        ),
      ),
    );
  }
}