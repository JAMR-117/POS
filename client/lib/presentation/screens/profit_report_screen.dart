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
  final ReportsRepository _repository = ReportsRepository();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$');
  
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  ProfitReportSummary? _reportData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Bloqueo de seguridad (RBAC)
    if (!widget.authController.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ACCESO DENEGADO: Solo administradores pueden ver la utilidad.'),
            backgroundColor: Colors.red,
          ),
        );
      });
      return;
    }
    _generateReport();
  }

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);
    final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
    
    final data = await _repository.getGrossProfitReport(_startDate, endOfDay);
    
    if (mounted) {
      setState(() {
        _reportData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: const Color(0xFF1F4E79)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _generateReport();
    }
  }

  Widget _buildKPICard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authController.isAdmin) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte de Utilidad Bruta'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.calendar_month, color: Colors.white),
            label: Text(
              '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _buildKPICard('Ventas Netas', _currencyFormat.format(_reportData!.totalVentas), Colors.blue.shade700, Icons.point_of_sale),
                      const SizedBox(width: 12),
                      _buildKPICard('Costo de Mercancía (COGS)', _currencyFormat.format(_reportData!.cogs), Colors.orange.shade700, Icons.inventory),
                      const SizedBox(width: 12),
                      _buildKPICard('Ganancia Bruta', _currencyFormat.format(_reportData!.gananciaBruta), Colors.green.shade700, Icons.attach_money),
                      const SizedBox(width: 12),
                      _buildKPICard('Margen Bruto', '${_reportData!.margenPorcentual.toStringAsFixed(2)}%', Colors.purple.shade700, Icons.pie_chart),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Top 10 Productos Más Rentables',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      elevation: 1,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                          columns: const [
                            DataColumn(label: Text('Producto')),
                            DataColumn(label: Text('Unidades Vendidas'), numeric: true),
                            DataColumn(label: Text('Utilidad Generada'), numeric: true),
                          ],
                          rows: _reportData!.topProductos.map((p) {
                            return DataRow(cells: [
                              DataCell(Text(p.descripcion, style: const TextStyle(fontWeight: FontWeight.w500))),
                              DataCell(Text(p.cantidadVendida.toStringAsFixed(2))),
                              DataCell(Text(_currencyFormat.format(p.utilidadGenerada), style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}