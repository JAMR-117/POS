import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'esc_pos_ticket_builder.dart';
import '../local/models.dart';

enum PrinterConnectionType {
  windowsSpooler, // Impresora térmica USB instalada en Windows vía Backend Local
  network,        // Impresora de Red Ethernet/Wi-Fi (Socket RAW TCP)
  systemDialog,   // Vista previa térmica / Diálogo del navegador
  disabled,       // Deshabilitada
}

class PrinterConfig {
  final PrinterConnectionType type;
  final String printerName; // Nombre de impresora en Windows (ej: POS-80, EPSON TM-T20)
  final String address;     // IP de impresora de red (ej: 192.168.1.200)
  final int port;           // Puerto de red (por defecto 9100)
  final String backendUrl;  // URL del backend local (por defecto http://127.0.0.1:8080)
  final PaperSize paperSize;

  const PrinterConfig({
    this.type = PrinterConnectionType.windowsSpooler,
    this.printerName = '',
    this.address = '192.168.1.200',
    this.port = 9100,
    this.backendUrl = 'http://127.0.0.1:8080',
    this.paperSize = PaperSize.mm80,
  });

  PrinterConfig copyWith({
    PrinterConnectionType? type,
    String? printerName,
    String? address,
    int? port,
    String? backendUrl,
    PaperSize? paperSize,
  }) {
    return PrinterConfig(
      type: type ?? this.type,
      printerName: printerName ?? this.printerName,
      address: address ?? this.address,
      port: port ?? this.port,
      backendUrl: backendUrl ?? this.backendUrl,
      paperSize: paperSize ?? this.paperSize,
    );
  }
}

class PrintResult {
  final bool success;
  final String message;
  final String? plainTextTicket;

  const PrintResult({
    required this.success,
    required this.message,
    this.plainTextTicket,
  });
}

class PrinterService {
  PrinterConfig _config;
  late EscPosTicketBuilder _builder;

  PrinterConfig get config => _config;

  PrinterService({PrinterConfig? config})
      : _config = config ?? const PrinterConfig() {
    _builder = EscPosTicketBuilder(paperSize: _config.paperSize);
    _loadFromPreferences();
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeStr = prefs.getString('pos_printer_type') ?? 'windowsSpooler';
      final name = prefs.getString('pos_printer_name') ?? '';
      final address = prefs.getString('pos_printer_address') ?? '192.168.1.200';
      final port = prefs.getInt('pos_printer_port') ?? 9100;
      final paperStr = prefs.getString('pos_printer_paper') ?? 'mm80';

      PrinterConnectionType connType;
      switch (typeStr) {
        case 'network':
          connType = PrinterConnectionType.network;
          break;
        case 'systemDialog':
          connType = PrinterConnectionType.systemDialog;
          break;
        case 'disabled':
          connType = PrinterConnectionType.disabled;
          break;
        case 'windowsSpooler':
        default:
          connType = PrinterConnectionType.windowsSpooler;
          break;
      }

      _config = _config.copyWith(
        type: connType,
        printerName: name,
        address: address,
        port: port,
        paperSize: paperStr == 'mm58' ? PaperSize.mm58 : PaperSize.mm80,
      );
      _builder = EscPosTicketBuilder(paperSize: _config.paperSize);
    } catch (e) {
      debugPrint('[PRINTER_PREFS] Error cargando preferencias de impresora: $e');
    }
  }

  Future<void> saveConfig(PrinterConfig newConfig) async {
    _config = newConfig;
    _builder = EscPosTicketBuilder(paperSize: _config.paperSize);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pos_printer_type', _config.type.name);
      await prefs.setString('pos_printer_name', _config.printerName);
      await prefs.setString('pos_printer_address', _config.address);
      await prefs.setInt('pos_printer_port', _config.port);
      await prefs.setString('pos_printer_paper', _config.paperSize.name);
    } catch (e) {
      debugPrint('[PRINTER_PREFS] Error persistiendo configuración: $e');
    }
  }

  /// Consulta la lista de impresoras físicas de Windows a través del puente Go local
  Future<List<String>> fetchInstalledPrinters() async {
    try {
      final uri = Uri.parse('${_config.backendUrl}/api/v1/printers');
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['printers'] is List) {
          return List<String>.from(data['printers']);
        }
      }
    } catch (e) {
      debugPrint('[PRINTER_API] Backend no disponible para listar impresoras: $e');
    }
    return [];
  }

  /// Despacha la impresión física de un ticket de venta
  Future<PrintResult> printSaleTicketAsync(
    TicketPrintData ticketData, {
    bool openCashDrawer = false,
  }) async {
    final plainText = _builder.buildPlainText(ticketData);

    if (_config.type == PrinterConnectionType.disabled) {
      return PrintResult(
        success: false,
        message: 'Impresora deshabilitada en Configuración.',
        plainTextTicket: plainText,
      );
    }

    if (_config.type == PrinterConnectionType.systemDialog) {
      return PrintResult(
        success: true,
        message: 'Vista previa generada para impresión por diálogo.',
        plainTextTicket: plainText,
      );
    }

    // Impresión física vía Backend en Go
    try {
      final bytes = _builder.buildTicket(ticketData, openCashDrawer: openCashDrawer);
      final rawBase64 = base64Encode(bytes);

      final payload = {
        'printer_type': _config.type == PrinterConnectionType.windowsSpooler ? 'windows_spooler' : 'network',
        'printer_name': _config.printerName,
        'address': _config.address,
        'port': _config.port,
        'raw_bytes_base64': rawBase64,
        'plain_text': plainText,
      };

      final uri = Uri.parse('${_config.backendUrl}/api/v1/print');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final target = _config.type == PrinterConnectionType.windowsSpooler
            ? _config.printerName
            : '${_config.address}:${_config.port}';
        return PrintResult(
          success: true,
          message: 'Ticket enviado con éxito a $target.',
          plainTextTicket: plainText,
        );
      } else {
        final errBody = jsonDecode(resp.body);
        final msg = errBody['message'] ?? 'Falla de comunicación con el puente de impresión.';
        return PrintResult(
          success: false,
          message: 'Error al imprimir: $msg',
          plainTextTicket: plainText,
        );
      }
    } catch (e) {
      return PrintResult(
        success: false,
        message: 'Servidor de impresión local (Go) inalcanzable. Verifique que iniciar_servidor.bat esté activo.',
        plainTextTicket: plainText,
      );
    }
  }

  /// Imprime una página de prueba con formato y corte de papel
  Future<PrintResult> printTestPage() async {
    final testData = TicketPrintData(
      negocioNombre: 'PRUEBA DE IMPRESORA TÉRMICA',
      rfc: 'XAXX010101000',
      direccion: 'Terminal POS Cerrajería',
      telefono: '555-0100',
      folio: 'TEST-${DateTime.now().millisecondsSinceEpoch % 10000}',
      fecha: DateTime.now(),
      cajero: 'Administrador',
      turnoId: 'PRUEBA',
      items: [
        SaleDetailItem(
          id: 'test-1',
          productoId: 'LLV-TEST',
          nombre: 'Prueba Llave Térmica 80mm',
          descripcion: 'Llave estándar de prueba',
          cantidad: 1.0,
          precioHistorico: 25.0,
          costoHistorico: 10.0,
          descuentoLinea: 0.0,
          totalLinea: 25.0,
        ),
      ],
      subtotal: 25.0,
      descuentoTotal: 0.0,
      total: 25.0,
      pagos: [PaymentMethodBreakdown(metodo: 'Prueba', monto: 25.0)],
      cambio: 0.0,
      piePagina: '¡Configuración de Impresión Validada Exitosamente!',
    );

    return await printSaleTicketAsync(testData, openCashDrawer: false);
  }

  /// Abre un modal emergente mostrando la vista previa térmica del ticket con opción de imprimir
  static void showThermalPreviewDialog(BuildContext context, String plainText, {VoidCallback? onPrintDirect}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Color(0xFF1F4E79)),
            SizedBox(width: 8),
            Text('Vista Previa de Ticket Térmico', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDE7),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: SingleChildScrollView(
              child: Text(
                plainText,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  height: 1.25,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          if (onPrintDirect != null)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79)),
              icon: const Icon(Icons.print, size: 16, color: Colors.white),
              label: const Text('Reintentar Impresión', style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.pop(ctx);
                onPrintDirect();
              },
            ),
        ],
      ),
    );
  }
}
