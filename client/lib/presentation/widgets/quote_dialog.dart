import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/string_utils.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/local/business_config.dart';
import '../../data/local/models.dart';

class QuoteDialog extends StatefulWidget {
  final List<SaleDetailItem> items;
  final double subtotal;
  final double descuentoTotal;
  final double total;
  final String? nombreNegocio;
  final String? leyendaNegocio;
  final String? logoBase64;
  final String? pdfSaveDirectory;
  final String? telefonoContacto;
  final String? emailContacto;
  final String clienteNombre;
  final PrinterService? printerService;

  const QuoteDialog({
    super.key,
    required this.items,
    required this.subtotal,
    required this.descuentoTotal,
    required this.total,
    this.nombreNegocio,
    this.leyendaNegocio,
    this.logoBase64,
    this.pdfSaveDirectory,
    this.telefonoContacto,
    this.emailContacto,
    this.clienteNombre = 'Público en General',
    this.printerService,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SaleDetailItem> items,
    required double subtotal,
    required double descuentoTotal,
    required double total,
    String? nombreNegocio,
    String? leyendaNegocio,
    String? logoBase64,
    String? pdfSaveDirectory,
    String? clienteNombre,
    PrinterService? printerService,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => QuoteDialog(
        items: items,
        subtotal: subtotal,
        descuentoTotal: descuentoTotal,
        total: total,
        nombreNegocio: nombreNegocio,
        leyendaNegocio: leyendaNegocio,
        logoBase64: logoBase64,
        pdfSaveDirectory: pdfSaveDirectory,
        clienteNombre: clienteNombre ?? 'Público en General',
        printerService: printerService,
      ),
    );
  }

  @override
  State<QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<QuoteDialog> {
  final GlobalKey _quoteBoundaryKey = GlobalKey();
  bool _mostrarComoFactura = false;
  bool _isExporting = false;

  String get _effectiveNegocioNombre =>
      (widget.nombreNegocio != null && widget.nombreNegocio!.isNotEmpty && widget.nombreNegocio != 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ')
          ? widget.nombreNegocio!
          : (BusinessConfig.current.negocioNombre.isNotEmpty ? BusinessConfig.current.negocioNombre : 'CARprog');

  String get _effectiveLeyenda =>
      widget.leyendaNegocio ?? BusinessConfig.current.negocioLeyenda;

  String? get _effectiveLogo =>
      widget.logoBase64 ?? BusinessConfig.current.logoBase64;

  String get _effectivePdfDir =>
      widget.pdfSaveDirectory ?? BusinessConfig.current.rutaGuardadoPdf;

  String get _effectiveTelefono =>
      widget.telefonoContacto ?? (BusinessConfig.current.negocioTelefono.isNotEmpty ? BusinessConfig.current.negocioTelefono : '555-123-4567');

  String get _effectiveEmail =>
      widget.emailContacto ?? (BusinessConfig.current.negocioEmail.isNotEmpty ? BusinessConfig.current.negocioEmail : 'contacto@carprog.com');

  Future<void> _printDocument(String folio, DateTime now) async {
    if (widget.printerService != null && widget.printerService!.config.type != PrinterConnectionType.disabled) {
      final ticketData = TicketPrintData(
        negocioNombre: _effectiveNegocioNombre,
        negocioLeyenda: _effectiveLeyenda,
        rfc: BusinessConfig.current.negocioRfc,
        direccion: BusinessConfig.current.negocioDireccion,
        telefono: _effectiveTelefono,
        mensajeSuperior: '*** ${_mostrarComoFactura ? "FACTURA CFDI 4.0 (PRUEBA)" : "COTIZACIÓN INFORMATIVA"} ***',
        folio: folio,
        fecha: now,
        cajero: 'VENTAS',
        turnoId: 'COTIZAR',
        clienteNombre: widget.clienteNombre,
        items: widget.items,
        subtotal: widget.subtotal,
        descuentoTotal: widget.descuentoTotal,
        total: widget.total,
        pagos: [PaymentMethodBreakdown(metodo: 'Cotizado', monto: widget.total)],
        cambio: 0.0,
        piePagina: 'Precios sujetos a cambio sin previo aviso.',
        mostrarCodigoBarras: BusinessConfig.current.ticketMostrarCodigoBarras,
      );
      final res = await widget.printerService!.printSaleTicketAsync(ticketData, openCashDrawer: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: res.success ? const Color(0xFF2E7D32) : Colors.orange.shade800,
          ),
        );
      }
    } else {
      await _saveAsPdf(folio, now);
    }
  }

  // Datos fiscales simulados basados en CAC950316GI4FA-     36004.pdf
  static const String _rfcEmisor = 'CAC950316GI4';
  static const String _razonSocialEmisor = 'CENTRO DE ABASTO CERRAJERO S.A. DE C.V.';
  static const String _domicilioEmisor = 'AV RIO DE CHURUBUSCO No. 1120, CP: 08900, IZTACALCO, CDMX, MEXICO';
  static const String _regimenEmisor = '601 - General de Ley Personas Morales';
  static const String _lugarExpedicion = '08900';

  static const String _serieFactura = 'A';
  static const String _folioFactura = '36004';
  static const String _uuidSimulado = 'D3DFC9C1-7A23-408C-A857-71CC0E5B7B78';
  static const String _csdEmisor = '00001000000718678493';
  static const String _csdSat = '00001000000723806214';
  static const String _fechaCertificacion = '2026-08-29T12:32:27';

  static const String _selloCfdi = 'Pn+DRQVt0dANmxbVdPgiarqVEBXx4V/ZZRUy4qH1DRUpsNdvyj8blodSN0YSwNJA7EkX7aMHcsl+VFdPZ6Su31aswiMOmiUIdGTn3GLcv+bC3/nEZxbIasr6+lTTmVazcXuHq+GWyksggm9dv+EWPLf4evTzcMTMgr';
  static const String _selloSat = 'qrEpobXLGGSNvx3egtD2Ds2tlaAKD0Mlsk8Y1YZ2O0TuJCAZKHAY9vqtnPajvfhoWGRBUfLa/Re7QCNH1pAJRdYRqLLyNxoijAP/G15FRd8MpHIA96l3eMGRQkll2UtvwDW23oEIoOZSmgQtijQKLxuYjIRlYy6J1iinoedQ==';
  static const String _cadenaOriginal = '||1.1|D3DFC9C1-7A23-408C-A857-71CC0E5B7B78|2026-08-29T12:32:27|TSP080724QW6|Pn+DRQVt0dANmxbVdPgiarqVEBXx4V/ZZRUy4qH1JDRUpsNdvyj8blodSN0YSwNJA7EkX7aMHcsl+VFdPKZ6Su31aswiMOmiUIdGTn3GLcv+bC3/nEZxbIasr6+lTTmVazcXuHq+GWyksggm9dv+EWPLf4evTzcMTMgrD||';

  String get _rfcReceptor => widget.clienteNombre == 'Público en General' ? 'XAXX010101000' : 'MUM2310204N7';
  String get _regimenReceptor => widget.clienteNombre == 'Público en General' ? '616 - Sin obligaciones fiscales' : '601 - General de Ley Personas Morales';
  String get _usoCfdi => widget.clienteNombre == 'Público en General' ? 'S01 - Sin efectos fiscales' : 'G03 - Gastos en general';

  double get _subtotalFiscal => double.parse((widget.total / 1.16).toStringAsFixed(2));
  double get _ivaFiscal => double.parse((widget.total - _subtotalFiscal).toStringAsFixed(2));


  Future<Uint8List?> _capturePngBytes() async {
    try {
      final boundary = _quoteBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturando imagen del documento: $e');
      return null;
    }
  }

  Future<void> _copyImageForWhatsApp() async {
    setState(() => _isExporting = true);
    try {
      final pngBytes = await _capturePngBytes();
      if (pngBytes == null) {
        throw Exception('No se pudo generar la imagen del documento.');
      }

      final imageBase64 = base64Encode(pngBytes);
      bool copiedViaBackend = false;
      try {
        final response = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/v1/clipboard/image'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image_base64': imageBase64}),
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          copiedViaBackend = true;
        }
      } catch (_) {}

      if (mounted) {
        if (copiedViaBackend) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Imagen copiada al Portapapeles de Windows. ¡Ve a WhatsApp y presiona Ctrl + V!'),
              backgroundColor: Color(0xFF2E7D32),
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Imagen procesada. En terminal Windows asegúrese de que el backend local esté activo para pegar con Ctrl+V.'),
              backgroundColor: Color(0xFF1F4E79),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _saveAsPdf(String folio, DateTime now) async {
    setState(() => _isExporting = true);
    try {
      final pngBytes = await _capturePngBytes();
      if (pngBytes == null) {
        throw Exception('No se pudo generar la captura visual del documento.');
      }

      final pdfDoc = pw.Document();
      final pdfImage = pw.MemoryImage(pngBytes);
      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context ctx) {
            return pw.Center(
              child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
            );
          },
        ),
      );

      final pdfBytes = await pdfDoc.save();
      final pdfBase64 = base64Encode(pdfBytes);

      final dateFormatted = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'Cotizacion_${folio}_$dateFormatted.pdf';
      final directory = _effectivePdfDir;

      String? savedPath;
      try {
        final response = await http.post(
          Uri.parse('http://127.0.0.1:8080/api/v1/files/save-pdf'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'directory': directory,
            'filename': filename,
            'pdf_base64': pdfBase64,
          }),
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            savedPath = data['path']?.toString();
          }
        }
      } catch (_) {}

      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ PDF guardado en: $savedPath'),
              backgroundColor: const Color(0xFF2E7D32),
              duration: const Duration(seconds: 7),
              action: SnackBarAction(
                label: '📂 Abrir / Ver',
                textColor: Colors.white,
                onPressed: () {
                  _openSavedFile(savedPath!);
                },
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ PDF generado ($filename) en carpeta configurada.'),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error guardando PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _openSavedFile(String path) async {
    try {
      await http.post(
        Uri.parse('http://127.0.0.1:8080/api/v1/files/open'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'path': path}),
      );
    } catch (_) {}
  }
  // ignore: unused_element
  String _generatePlainText(String folio, String fechaStr) {
    final buffer = StringBuffer();
    if (!_mostrarComoFactura) {
      buffer.writeln('====================================');
      buffer.writeln('       $_effectiveNegocioNombre');
      buffer.writeln('  TEL/WA: $_effectiveTelefono');
      buffer.writeln('  EMAIL:  $_effectiveEmail');
      buffer.writeln('====================================');
      buffer.writeln('*** COTIZACIÓN INFORMATIVA ***');
      buffer.writeln('(Precios sujetos a cambio)');
      buffer.writeln('------------------------------------');
      buffer.writeln('Folio:   $folio');
      buffer.writeln('Fecha:   $fechaStr');
      buffer.writeln('Cliente: ${widget.clienteNombre}');
      buffer.writeln('------------------------------------');
      buffer.writeln('CANT.  DESCRIPCIÓN          TOTAL');
      buffer.writeln('------------------------------------');

      for (final it in widget.items) {
        final isGranel = (it.cantidad % 1 != 0);
        final qtyStr = it.cantidad.toStringAsFixed(isGranel ? 3 : 0).padRight(6);
        final totalStr = '\$${it.totalLinea.toStringAsFixed(2)}'.padLeft(9);
        final desc = it.nombre.isNotEmpty ? it.nombre : it.descripcion;

        buffer.writeln('$qtyStr $desc');
        buffer.writeln('       P.U: \$${it.precioHistorico.toStringAsFixed(2)} -> $totalStr');
        if (it.descuentoLinea > 0) {
          buffer.writeln('       Descuento: -\$${it.descuentoLinea.toStringAsFixed(2)}');
        }
      }

      buffer.writeln('====================================');
      buffer.writeln('SUBTOTAL:         \$${widget.subtotal.toStringAsFixed(2)}');
      if (widget.descuentoTotal > 0) {
        buffer.writeln('DESCUENTO:       -\$${widget.descuentoTotal.toStringAsFixed(2)}');
      }
      buffer.writeln('TOTAL ESTIMADO:   \$${widget.total.toStringAsFixed(2)}');
      buffer.writeln('(${numeroALetras(widget.total)})');
      buffer.writeln('====================================');
      buffer.writeln('¡Agradecemos su preferencia!');
      buffer.writeln('* Esta cotización no reserva inventario *');
    } else {
      buffer.writeln('====================================');
      buffer.writeln('       FACTURA CFDI 4.0 (PRUEBA)');
      buffer.writeln(_razonSocialEmisor);
      buffer.writeln('RFC: $_rfcEmisor | Reg: $_regimenEmisor');
      buffer.writeln('Serie: $_serieFactura - Folio: $_folioFactura');
      buffer.writeln('UUID: $_uuidSimulado');
      buffer.writeln('Cliente: ${widget.clienteNombre} (RFC: $_rfcReceptor)');
      buffer.writeln('Uso CFDI: $_usoCfdi | Método: PUE | Forma: 01');
      buffer.writeln('------------------------------------');
      for (final it in widget.items) {
        final claveSat = it.esServicio ? '72154013' : '46171500';
        final claveUnidad = it.esServicio ? 'E48' : 'H87';
        final desc = it.nombre.isNotEmpty ? it.nombre : it.descripcion;
        buffer.writeln('${it.cantidad}x [$claveSat - $claveUnidad] $desc');
        buffer.writeln('   P/U: \$${(it.precioHistorico / 1.16).toStringAsFixed(2)} | Importe: \$${(it.totalLinea / 1.16).toStringAsFixed(2)}');
      }
      buffer.writeln('------------------------------------');
      buffer.writeln('Subtotal:  \$$_subtotalFiscal');
      buffer.writeln('IVA (16%): \$$_ivaFiscal');
      buffer.writeln('Total:     \$${widget.total.toStringAsFixed(2)}');
      buffer.writeln('(${numeroALetras(widget.total)})');
      buffer.writeln('====================================');
      buffer.writeln('Sello CFDI: $_selloCfdi');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final folio = 'COT-${now.millisecondsSinceEpoch.toString().safeSub(7)}';

    final dialogWidth = 620.0.clamp(360.0, MediaQuery.sizeOf(context).width * 0.95);
    final dialogHeight = 680.0.clamp(480.0, MediaQuery.sizeOf(context).height * 0.88);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera Modal con Switch interactivo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1F4E79),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Icon(
                    _mostrarComoFactura ? Icons.receipt_long : Icons.request_quote_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _mostrarComoFactura
                          ? 'Comprobante Fiscal Digital (CFDI 4.0 - Modo Prueba)'
                          : 'Ticket Digital de Cotización',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Switch Modo Prueba Factura (Compacto)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '🧾 Factura (Prueba)',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: _mostrarComoFactura,
                            activeTrackColor: const Color(0xFF64B5F6),
                            thumbColor: WidgetStateProperty.all(Colors.white),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (val) => setState(() => _mostrarComoFactura = val),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Cuerpo del Documento (Desplazable y Capturable)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _quoteBoundaryKey,
                  child: Container(
                    color: Colors.white,
                    child: _mostrarComoFactura
                        ? _buildCfdiDocumentView(now, fechaStr)
                        : _buildQuoteDocumentView(folio, fechaStr),
                  ),
                ),
              ),
            ),

            // Barra Inferior de Acciones Profesionales (4 opciones limpias y directas)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F7FA),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366), // WhatsApp Green
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: _isExporting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.copy, size: 16),
                      label: const Text('📋 Copiar Imagen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _isExporting ? null : _copyImageForWhatsApp,
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F4E79),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: _isExporting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('📄 Guardar PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _isExporting ? null : () => _saveAsPdf(folio, now),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF37474F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('🖨️ Imprimir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _isExporting ? null : () => _printDocument(folio, now),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade800,
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VISTA 1: COTIZACIÓN LIMPIA (SIN FISCALES)
  // ---------------------------------------------------------------------------
  Widget _buildQuoteDocumentView(String folio, String fechaStr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado Personalizado
          if (_effectiveLogo != null && _effectiveLogo!.isNotEmpty) ...[
            Center(
              child: Image.memory(
                base64Decode(_effectiveLogo!),
                height: 55,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            _effectiveNegocioNombre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
          ),
          if (_effectiveLeyenda.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _effectiveLeyenda,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'WhatsApp: $_effectiveTelefono  |  Email: $_effectiveEmail',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: const Text(
              'COTIZACIÓN INFORMATIVA (Precios sujetos a cambio)',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF795548)),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Folio: $folio', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(fechaStr, style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Cliente: ${widget.clienteNombre}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Divider(height: 20),

          // Tabla de Partidas
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            color: const Color(0xFFECEFF1),
            child: const Row(
              children: [
                SizedBox(width: 45, child: Text('CANT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Expanded(child: Text('DESCRIPCIÓN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 75, child: Text('P. UNIT', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 75, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ...widget.items.map((it) {
            final isGranel = (it.cantidad % 1 != 0);
            final qtyStr = it.cantidad.toStringAsFixed(isGranel ? 3 : 0);
            final desc = it.nombre.isNotEmpty ? it.nombre : it.descripcion;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: [
                  SizedBox(width: 45, child: Text(qtyStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  Expanded(
                    child: Text(
                      desc,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 75, child: Text('\$${it.precioHistorico.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                  SizedBox(width: 75, child: Text('\$${it.totalLinea.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          }),
          const Divider(height: 20),

          // Desglose de Totales
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 280,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal:', style: TextStyle(fontSize: 12)),
                      Text('\$${widget.subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  if (widget.descuentoTotal > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Descuento:', style: TextStyle(fontSize: 12, color: Colors.green)),
                        Text('-\$${widget.descuentoTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(child: Text('TOTAL ESTIMADO:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Text('\$${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '(${numeroALetras(widget.total)})',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          const Text(
            '¡Gracias por su preferencia!\n* Precios sujetos a cambio sin previo aviso. Esta cotización no reserva inventario *',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VISTA 2: FACTURA CFDI 4.0 SIMULADA (BASADA EN CAC950316GI4FA- 36004.pdf)
  // ---------------------------------------------------------------------------
  Widget _buildCfdiDocumentView(DateTime now, String fechaStr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFB0BEC5)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner de prueba
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: const Color(0xFFE3F2FD),
            child: const Text(
              '*** COMPROBANTE FISCAL DIGITAL POR INTERNET (CFDI 4.0) - SIMULACIÓN OFFLINE ***',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
            ),
          ),
          const SizedBox(height: 12),

          // Encabezado Emisor + Datos de Factura
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(_razonSocialEmisor, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79))),
                    const SizedBox(height: 2),
                    const Text('R.F.C.: $_rfcEmisor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const Text('Régimen Fiscal: $_regimenEmisor', style: TextStyle(fontSize: 11)),
                    const Text('Domicilio Fiscal: $_domicilioEmisor', style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text('Lugar de expedición: $_lugarExpedicion | Fecha: ${now.toIso8601String().safePrefix(19)}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEFF1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFCFD8DC)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FACTURA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79))),
                      Text('Serie: $_serieFactura  |  Folio: $_folioFactura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('Tipo Comprobante: (I) Ingreso', style: TextStyle(fontSize: 10)),
                      Text('Método de Pago: (PUE) Una sola exhibición', style: TextStyle(fontSize: 10)),
                      Text('Forma de Pago: (01) Efectivo', style: TextStyle(fontSize: 10)),
                      Text('Moneda: MXN - Peso Mexicano', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Receptor / Cliente
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FACTURADO A (RECEPTOR):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                Text(widget.clienteNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text('R.F.C.: $_rfcReceptor  |  Régimen Fiscal: $_regimenReceptor', style: const TextStyle(fontSize: 11)),
                Text('Uso de CFDI: $_usoCfdi  |  Domicilio Fiscal C.P.: 57000', style: const TextStyle(fontSize: 10, color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tabla con Claves SAT (ClaveProdServ, ClaveUnidad, ObjetoImp)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            color: const Color(0xFF1F4E79),
            child: const Row(
              children: [
                SizedBox(width: 35, child: Text('CANT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
                SizedBox(width: 65, child: Text('CLAVE SAT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
                Expanded(child: Text('DESCRIPCIÓN / UNIDAD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
                SizedBox(width: 65, child: Text('P/U BASE', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
                SizedBox(width: 65, child: Text('IMPORTE', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))),
              ],
            ),
          ),
          ...widget.items.map((it) {
            final claveSat = it.esServicio ? '72154013' : '46171500';
            final claveUnidad = it.esServicio ? 'E48' : 'H87';
            final unidadDesc = it.esServicio ? 'Servicio' : 'Pieza';
            final basePU = it.precioHistorico / 1.16;
            final baseImporte = it.totalLinea / 1.16;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
              child: Row(
                children: [
                  SizedBox(width: 35, child: Text(it.cantidad.toStringAsFixed(0), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  SizedBox(width: 65, child: Text('$claveSat\n$claveUnidad', style: const TextStyle(fontSize: 9, color: Colors.black54))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.nombre.isNotEmpty ? it.nombre : it.descripcion, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        Text('Unidad: $unidadDesc | ObjetoImp: 02 (Sí objeto)', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                      ],
                    ),
                  ),
                  SizedBox(width: 65, child: Text('\$${basePU.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                  SizedBox(width: 65, child: Text('\$${baseImporte.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),

          // Desglose de Totales Fiscales
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Importe con letra:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(numeroALetras(widget.total), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
                    const SizedBox(height: 6),
                    const Text('"Este documento es una representación impresa de un CFDI v4.0"', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.black54)),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:', style: TextStyle(fontSize: 12)),
                        Text('\$${_subtotalFiscal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Descuento:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        Text('\$0.00', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('I.V.A. (16% Trasladado):', style: TextStyle(fontSize: 12)),
                        Text('\$${_ivaFiscal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('\$${widget.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Timbre Fiscal Digital del SAT (Sello, UUID, CSD y QR)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Código QR Fiscal Simulado
              Container(
                width: 90,
                height: 90,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black87),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_2, size: 70, color: Colors.black87),
                    Text('SAT QR', style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Cadenas y Sellos
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text('Folio Fiscal: $_uuidSimulado', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold))),
                        Text('Fecha Cert: $_fechaCertificacion', style: TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                    Text('No. Serie CSD Emisor: $_csdEmisor | No. Serie CSD SAT: $_csdSat', style: TextStyle(fontSize: 9, color: Colors.black54)),
                    SizedBox(height: 4),
                    Text('Sello Digital del CFDI:', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                    Text(_selloCfdi, style: TextStyle(fontSize: 7, fontFamily: 'monospace', color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text('Sello Digital del SAT:', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                    Text(_selloSat, style: TextStyle(fontSize: 7, fontFamily: 'monospace', color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text('Cadena Original del complemento de certificación digital del SAT:', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                    Text(_cadenaOriginal, style: TextStyle(fontSize: 7, fontFamily: 'monospace', color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
