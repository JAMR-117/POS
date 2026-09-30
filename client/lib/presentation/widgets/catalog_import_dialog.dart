import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Importaciones requeridas para resolver FilePickerResult y CsvToListConverter
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

import '../../data/repositories/product_repository.dart';

class CatalogImportDialog extends StatefulWidget {
  const CatalogImportDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CatalogImportDialog(),
    );
  }

  @override
  State<CatalogImportDialog> createState() => _CatalogImportDialogState();
}

class _CatalogImportDialogState extends State<CatalogImportDialog> {
  final ProductRepository _productRepository = ProductRepository();
  
  bool _isProcessing = false;
  String? _statusMessage;
  String? _errorMessage;
  double _progressValue = 0.0;

  Future<void> _pickAndProcessFile() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = 'Seleccionando archivo...';
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, 
      );

      if (result == null) {
        setState(() => _statusMessage = null);
        return;
      }

      setState(() {
        _isProcessing = true;
        _statusMessage = 'Leyendo y validando formato CSV...';
        _progressValue = 0.2;
      });

      final bytes = result.files.single.bytes ?? File(result.files.single.path!).readAsBytesSync();
      final csvString = utf8.decode(bytes);

      final List<List<dynamic>> csvTable = const CsvToListConverter(eol: '\n', fieldDelimiter: ',').convert(csvString);

      if (csvTable.isEmpty || csvTable.length == 1) {
        throw Exception('El archivo está vacío o solo contiene la cabecera.');
      }

      final header = csvTable.first.map((e) => e.toString().toLowerCase().trim()).toList();
      
      final colCodigo = header.indexWhere((h) => h.contains('codigo') || h.contains('sku') || h.contains('código'));
      final colDesc = header.indexWhere((h) => h.contains('descrip'));
      final colPrecioC = header.indexWhere((h) => h.contains('compra') || h.contains('costo'));
      final colPrecioV = header.indexWhere((h) => h.contains('venta') || h.contains('precio'));
      final colStock = header.indexWhere((h) => h.contains('stock') || h.contains('existencia'));
      final colDepto = header.indexWhere((h) => h.contains('departamento') || h.contains('categoria'));

      if (colCodigo == -1 || colDesc == -1 || colPrecioV == -1 || colStock == -1) {
        throw Exception('Faltan columnas obligatorias. Se requiere: Código, Descripción, Precio de Venta y Stock.');
      }

      setState(() {
        _statusMessage = 'Estructurando registros para SQLite...';
        _progressValue = 0.5;
      });

      List<Map<String, dynamic>> parsedData = [];
      for (int i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (row.length <= colDesc) continue;

        parsedData.add({
          'codigo': row[colCodigo],
          'descripcion': row[colDesc],
          'precio_compra': colPrecioC != -1 ? (num.tryParse(row[colPrecioC].toString()) ?? 0.0) : 0.0,
          'precio_venta': num.tryParse(row[colPrecioV].toString()) ?? 0.0,
          'stock': num.tryParse(row[colStock].toString()) ?? 0.0,
          'departamento': colDepto != -1 && row.length > colDepto ? row[colDepto] : 'General',
        });
      }

      setState(() {
        _statusMessage = 'Insertando ${parsedData.length} productos en la base de datos...';
        _progressValue = 0.8;
      });

      final importedCount = await _productRepository.importCatalogFromCSV(parsedData);

      setState(() => _progressValue = 1.0);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$importedCount productos importados exitosamente.'),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _statusMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.upload_file, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Importación Masiva (CSV)'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Seleccione un archivo CSV delimitado por comas. El archivo debe incluir en su primera fila las cabeceras:\n\n• Código\n• Descripción\n• Precio Compra\n• Precio Venta\n• Stock\n• Departamento (Opcional)',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),

            if (_isProcessing) ...[
              LinearProgressIndicator(value: _progressValue, backgroundColor: Colors.grey.shade300, color: const Color(0xFF1F4E79)),
              const SizedBox(height: 12),
              Text(_statusMessage ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
            ] else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F4E79),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                icon: const Icon(Icons.folder_open),
                label: const Text('SELECCIONAR ARCHIVO CSV', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _pickAndProcessFile,
              ),
            ]
          ],
        ),
      ),
      actions: [
        if (!_isProcessing)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }
}