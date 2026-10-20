import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const String _defaultMigratedCsvPath = r'C:\POS\migracion\catalogo_migrado_pos.csv';
  static const String _assetMigratedCsvPath = 'assets/catalogo_migrado_pos.csv';
  
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

      final pickedFile = result.files.single;
      String csvString;

      if (pickedFile.bytes != null) {
        csvString = utf8.decode(pickedFile.bytes!, allowMalformed: true);
      } else if (!kIsWeb && pickedFile.path != null) {
        csvString = await io.File(pickedFile.path!).readAsString();
      } else {
        throw Exception('No fue posible leer el contenido del archivo seleccionado.');
      }

      await _processCsvString(csvString);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _statusMessage = null;
      });
    }
  }

  Future<void> _loadPredefinedMigratedCatalog() async {
    setState(() {
      _errorMessage = null;
      _statusMessage = 'Cargando catálogo migrado...';
    });

    try {
      String csvString = '';

      if (kIsWeb) {
        // En Web, cargar de manera nativa y transparente desde assets
        csvString = await rootBundle.loadString(_assetMigratedCsvPath);
      } else {
        // En Desktop, intentar leer primero desde la ruta física local
        final localFile = io.File(_defaultMigratedCsvPath);
        if (localFile.existsSync()) {
          csvString = await localFile.readAsString();
        } else {
          // Respaldo inmediato desde assets si no está en C:\POS\migracion\
          csvString = await rootBundle.loadString(_assetMigratedCsvPath);
        }
      }

      if (csvString.trim().isEmpty) {
        throw Exception('El archivo de catálogo migrado está vacío.');
      }

      await _processCsvString(csvString);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Error al cargar catálogo migrado: ${e.toString().replaceAll('Exception: ', '')}';
        _statusMessage = null;
      });
    }
  }

  Future<void> _processCsvString(String csvString) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Validando estructura del catálogo...';
      _progressValue = 0.2;
    });

    final List<List<dynamic>> csvTable = const CsvToListConverter(
      eol: '\n', 
      fieldDelimiter: ',',
      shouldParseNumbers: false,
    ).convert(csvString);

    if (csvTable.isEmpty || csvTable.length == 1) {
      throw Exception('El archivo está vacío o solo contiene la cabecera.');
    }

    final header = csvTable.first.map((e) => e.toString().toLowerCase().trim()).toList();
    
    // Mapeo dinámico y exhaustivo de columnas enriquecidas
    final colCodigo = header.indexWhere((h) => h == 'codigo' || h == 'código' || h.contains('codigo') || h.contains('sku'));
    final colSku = header.indexWhere((h) => h == 'sku');
    final colNombre = header.indexWhere((h) => h == 'nombre');
    final colDesc = header.indexWhere((h) => h.contains('descrip'));
    final colMarca = header.indexWhere((h) => h == 'marca');
    final colMolde = header.indexWhere((h) => h.contains('equivalencia') || h.contains('molde'));
    final colUbicacion = header.indexWhere((h) => h.contains('ubicacion') || h.contains('ubicación') || h.contains('gaveta'));
    final colPrecioC = header.indexWhere((h) => h.contains('compra') || h.contains('costo'));
    final colPrecioV = header.indexWhere((h) => h == 'precio_venta' || h.contains('venta') || h == 'precio');
    final colPrecioCerrajero = header.indexWhere((h) => h.contains('cerrajero'));
    final colPrecioTaller = header.indexWhere((h) => h.contains('taller'));
    final colPrecioMayoreo = header.indexWhere((h) => h.contains('precio_mayoreo') || h == 'mayoreo');
    final colCantMayoreo = header.indexWhere((h) => h.contains('cantidad_mayoreo'));
    final colStock = header.indexWhere((h) => h.contains('stock') || h.contains('existencia'));
    final colStockMin = header.indexWhere((h) => h.contains('stock_minimo') || h.contains('minimo'));
    final colDepto = header.indexWhere((h) => h.contains('departamento') || h.contains('categoria') || h == 'depto');
    final colGranel = header.indexWhere((h) => h.contains('granel'));
    final colServicio = header.indexWhere((h) => h.contains('servicio'));
    final colInsumoId = header.indexWhere((h) => h.contains('insumo'));

    if (colCodigo == -1 || (colDesc == -1 && colNombre == -1) || colPrecioV == -1) {
      throw Exception('Faltan columnas obligatorias. Se requiere como mínimo: Código, Nombre/Descripción y Precio de Venta.');
    }

    setState(() {
      _statusMessage = 'Estructurando registros enriquecidos para SQLite...';
      _progressValue = 0.5;
    });

    List<Map<String, dynamic>> parsedData = [];
    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.isEmpty) continue;
      
      final rawCodigo = colCodigo != -1 && row.length > colCodigo ? row[colCodigo]?.toString().trim() : '';
      if (rawCodigo == null || rawCodigo.isEmpty) continue;

      final rawDesc = colDesc != -1 && row.length > colDesc ? row[colDesc]?.toString().trim() : '';
      final rawNombre = colNombre != -1 && row.length > colNombre ? row[colNombre]?.toString().trim() : '';
      final nombreFinal = (rawNombre != null && rawNombre.isNotEmpty) ? rawNombre : (rawDesc ?? rawCodigo);
      final descFinal = (rawDesc != null && rawDesc.isNotEmpty) ? rawDesc : nombreFinal;

      final pCompra = colPrecioC != -1 && row.length > colPrecioC ? (num.tryParse(row[colPrecioC].toString())?.toDouble() ?? 0.0) : 0.0;
      final pVenta = colPrecioV != -1 && row.length > colPrecioV ? (num.tryParse(row[colPrecioV].toString())?.toDouble() ?? 0.0) : 0.0;
      final pCerrajero = colPrecioCerrajero != -1 && row.length > colPrecioCerrajero ? num.tryParse(row[colPrecioCerrajero].toString())?.toDouble() : null;
      final pTaller = colPrecioTaller != -1 && row.length > colPrecioTaller ? num.tryParse(row[colPrecioTaller].toString())?.toDouble() : null;
      final pMayoreo = colPrecioMayoreo != -1 && row.length > colPrecioMayoreo ? num.tryParse(row[colPrecioMayoreo].toString())?.toDouble() : null;
      final cantMayoreo = colCantMayoreo != -1 && row.length > colCantMayoreo ? num.tryParse(row[colCantMayoreo].toString())?.toDouble() : null;
      final stockVal = colStock != -1 && row.length > colStock ? (num.tryParse(row[colStock].toString())?.toDouble() ?? 0.0) : 0.0;
      final stockMinVal = colStockMin != -1 && row.length > colStockMin ? (num.tryParse(row[colStockMin].toString())?.toDouble() ?? 5.0) : 5.0;
      final esGranelVal = colGranel != -1 && row.length > colGranel ? (int.tryParse(row[colGranel].toString()) ?? (stockVal % 1 != 0 ? 1 : 0)) : (stockVal % 1 != 0 ? 1 : 0);
      final esServVal = colServicio != -1 && row.length > colServicio ? (int.tryParse(row[colServicio].toString()) ?? 0) : 0;

      final rawMarca = colMarca != -1 && row.length > colMarca ? row[colMarca]?.toString().trim() : null;
      final rawMolde = colMolde != -1 && row.length > colMolde ? row[colMolde]?.toString().trim() : null;
      final rawUbi = colUbicacion != -1 && row.length > colUbicacion ? row[colUbicacion]?.toString().trim() : null;
      final rawDepto = colDepto != -1 && row.length > colDepto ? row[colDepto]?.toString().trim() : 'General';
      final rawSku = colSku != -1 && row.length > colSku ? row[colSku]?.toString().trim() : rawCodigo;
      final rawInsumo = colInsumoId != -1 && row.length > colInsumoId ? row[colInsumoId]?.toString().trim() : null;

      parsedData.add({
        'codigo': rawCodigo,
        'sku': rawSku ?? rawCodigo,
        'nombre': nombreFinal,
        'descripcion': descFinal,
        'marca': (rawMarca != null && rawMarca.isNotEmpty) ? rawMarca : 'Genérica',
        'codigo_equivalencia': (rawMolde != null && rawMolde.isNotEmpty) ? rawMolde : null,
        'ubicacion': (rawUbi != null && rawUbi.isNotEmpty) ? rawUbi : null,
        'departamento': (rawDepto != null && rawDepto.isNotEmpty) ? rawDepto : 'General',
        'precio_compra': pCompra,
        'precio_venta': pVenta,
        'precio_cerrajero': pCerrajero,
        'precio_taller': pTaller,
        'precio_mayoreo': pMayoreo,
        'cantidad_mayoreo': cantMayoreo,
        'stock_actual': stockVal,
        'stock_minimo': stockMinVal,
        'es_a_granel': esGranelVal,
        'es_servicio': esServVal,
        'insumo_vinculado_id': (rawInsumo != null && rawInsumo.isNotEmpty) ? rawInsumo : null,
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
          content: Text('$importedCount productos importados y enriquecidos exitosamente.'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.upload_file, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Importación Masiva (ADM-03)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cargue el catálogo unificado con marcas, gavetas y moldes equivalentes. Soporta importación enriquecida SQLite con ConflictAlgorithm.replace.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 18),
            
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            if (_isProcessing) ...[
              LinearProgressIndicator(
                value: _progressValue, 
                backgroundColor: Colors.grey.shade300, 
                color: const Color(0xFF1F4E79),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage ?? '', 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F4E79), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              // BOTÓN PRINCIPAL RÁPIDO: CARGAR CATÁLOGO MIGRADO
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  elevation: 2,
                ),
                onPressed: _loadPredefinedMigratedCatalog,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, color: Colors.amber, size: 22),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '⚡ Cargar Catálogo Migrado',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  kIsWeb 
                    ? '(Carga instantánea desde assets integrados)' 
                    : r'(Desde C:\POS\migracion\catalogo_migrado_pos.csv o assets)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 14),
              const Center(
                child: Text(
                  '— o seleccionar otro archivo —', 
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 14),

              // BOTÓN SECUNDARIO: EXPLORADOR DE ARCHIVOS
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F4E79),
                  side: const BorderSide(color: Color(0xFF1F4E79)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _pickAndProcessFile,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Seleccionar cualquier archivo CSV',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
