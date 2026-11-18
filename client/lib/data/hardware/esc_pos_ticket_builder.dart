import 'dart:convert';
import 'dart:typed_data';
import '../../core/string_utils.dart';
import '../local/models.dart';

enum PaperSize {
  mm58(32), // 32 caracteres por columna (estándar 58mm fuente A)
  mm80(48); // 48 caracteres por columna (estándar 80mm fuente A)

  final int maxChars;
  const PaperSize(this.maxChars);
}

/// Datos requeridos para imprimir el comprobante de venta físico
class TicketPrintData {
  final String negocioNombre;
  final String? negocioLeyenda;
  final String? rfc;
  final String? direccion;
  final String? telefono;
  final String? mensajeSuperior;
  final String folio;
  final DateTime fecha;
  final String cajero;
  final String turnoId;
  final String clienteNombre;
  final List<SaleDetailItem> items;
  final double subtotal;
  final double descuentoTotal;
  final double total;
  final double ajusteRedondeo;
  final List<PaymentMethodBreakdown> pagos;
  final double cambio;
  final String piePagina;
  final String? garantia;
  final String? notasTicket;
  final String? fontFamily;

  // Banderas de configuración de plantilla
  final bool mostrarLogo;
  final bool mostrarNombre;
  final bool mostrarContacto;
  final bool mostrarFolioFecha;
  final bool mostrarCajero;
  final bool mostrarCliente;
  final bool mostrarDescuentosRedondeo;
  final bool mostrarTotalLetra;
  final bool mostrarCodigoBarras;

  const TicketPrintData({
    required this.negocioNombre,
    this.negocioLeyenda,
    this.rfc,
    this.direccion,
    this.telefono,
    this.mensajeSuperior,
    required this.folio,
    required this.fecha,
    required this.cajero,
    required this.turnoId,
    this.clienteNombre = 'Público en General',
    required this.items,
    required this.subtotal,
    this.descuentoTotal = 0.0,
    required this.total,
    this.ajusteRedondeo = 0.0,
    required this.pagos,
    required this.cambio,
    this.piePagina = '¡Gracias por su preferencia!',
    this.garantia,
    this.notasTicket,
    this.fontFamily,
    this.mostrarLogo = true,
    this.mostrarNombre = true,
    this.mostrarContacto = true,
    this.mostrarFolioFecha = true,
    this.mostrarCajero = true,
    this.mostrarCliente = true,
    this.mostrarDescuentosRedondeo = true,
    this.mostrarTotalLetra = true,
    this.mostrarCodigoBarras = true,
  });
}

/// Generador binario nativo de secuencias ESC/POS y previsualización térmica
class EscPosTicketBuilder {
  final PaperSize paperSize;
  final BytesBuilder _buffer = BytesBuilder();

  // Comandos estándar ESC/POS
  static const List<int> _escInit = [0x1B, 0x40]; // ESC @ (Inicializar)
  static const List<int> _selectCodePage = [0x1B, 0x74, 0x10]; // ESC t 16 (WPC1252 para compatibilidad internacional)
  static const List<int> _fontA = [0x1B, 0x4D, 0x00]; // ESC M 0 (Estándar Fuente A)
  static const List<int> _fontB = [0x1B, 0x4D, 0x01]; // ESC M 1 (Condensada Fuente B)
  static const List<int> _alignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> _alignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> _alignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  static const List<int> _boldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> _boldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> _doubleSize = [0x1D, 0x21, 0x11]; // GS ! 0x11 (2x Alto y Ancho)
  static const List<int> _normalSize = [0x1D, 0x21, 0x00]; // GS ! 0x00 (Normal)
  static const List<int> _cutPaper = [0x1D, 0x56, 0x42, 0x00]; // GS V 66 0 (Corte parcial)
  static const List<int> _openDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA]; // Pulso cajón

  /// Normaliza y sanitiza texto para prevenir caracteres extraños en impresoras térmicas
  /// de arquitectura genérica o firmware fijado en CP437/CP850.
  static String sanitizeTextForThermal(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('¿', '')
        .replaceAll('¡', '')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
  }

  EscPosTicketBuilder({this.paperSize = PaperSize.mm80});

  Uint8List buildTicket(TicketPrintData data, {bool openCashDrawer = false}) {
    _buffer.clear();

    // 1. Inicializar impresora y página de códigos internacional
    _buffer.add(_escInit);
    _buffer.add(_selectCodePage);
    if (data.fontFamily != null && data.fontFamily!.toLowerCase().contains('fuente b')) {
      _buffer.add(_fontB);
    } else {
      _buffer.add(_fontA);
    }

    if (openCashDrawer) {
      _buffer.add(_openDrawer);
    }

    // 2. Encabezado del negocio (Estilo CARprog / El Gran Tlapalero)
    _buffer.add(_alignCenter);
    if (data.mostrarNombre) {
      _buffer.add(_boldOn);
      _buffer.add(_doubleSize);
      _writeText('${data.negocioNombre}\n');
      _buffer.add(_normalSize);
      _buffer.add(_boldOff);

      if (data.negocioLeyenda != null && data.negocioLeyenda!.isNotEmpty) {
        _writeText('${data.negocioLeyenda}\n');
      }
    }

    if (data.mostrarContacto) {
      if (data.direccion != null && data.direccion!.isNotEmpty) {
        _writeText('${data.direccion}\n');
      }
      if (data.rfc != null && data.rfc!.isNotEmpty) {
        _writeText('RFC: ${data.rfc}\n');
      }
      if (data.telefono != null && data.telefono!.isNotEmpty) {
        _writeText('TEL: ${data.telefono}\n');
      }
    }

    if (data.mensajeSuperior != null && data.mensajeSuperior!.isNotEmpty) {
      _writeText('${data.mensajeSuperior}\n');
    }

    _writeDivider('=');

    // 3. Metadatos de la Venta
    _buffer.add(_alignLeft);
    if (data.mostrarFolioFecha) {
      _writeText('FOLIO: ${data.folio}\n');
      _writeText('FECHA: ${_formatDate(data.fecha)}\n');
    }
    if (data.mostrarCliente) {
      _writeText('CLIENTE: ${data.clienteNombre}\n');
    }
    if (data.mostrarCajero) {
      _writeText('CAJERO: ${data.cajero} | TURNO: ${data.turnoId.safePrefix(8)}\n');
    }

    _writeDivider('-');

    // 4. Cabecera de Partidas
    _buffer.add(_boldOn);
    _writeText('${_formatTwoColumns('CANT  DESCRIPCIÓN', 'TOTAL', paperSize.maxChars)}\n');
    _buffer.add(_boldOff);

    _writeDivider('-');

    // 5. Detalle de Artículos
    for (final item in data.items) {
      final bool isGranel = (item.cantidad % 1 != 0);
      final String qtyStr = item.cantidad.toStringAsFixed(isGranel ? 3 : 0);
      final String lineLeft = '$qtyStr x \$${item.precioHistorico.toStringAsFixed(2)}  ${item.descripcion}';
      final String lineTotal = '\$${item.totalLinea.toStringAsFixed(2)}';

      if (lineLeft.length + lineTotal.length + 1 <= paperSize.maxChars) {
        _writeText('${_formatTwoColumns(lineLeft, lineTotal, paperSize.maxChars)}\n');
      } else {
        _writeText('$qtyStr x ${item.descripcion}\n');
        _writeText('${_formatTwoColumns('  P.U. \$${item.precioHistorico.toStringAsFixed(2)}', lineTotal, paperSize.maxChars)}\n');
      }

      if (data.mostrarDescuentosRedondeo && item.descuentoLinea > 0) {
        _writeText('${_formatTwoColumns('  (Desc.)', '-\$${item.descuentoLinea.toStringAsFixed(2)}', paperSize.maxChars)}\n');
      }
    }

    _writeDivider('-');

    // 6. Totales y Liquidación (con fallback seguro en caso de desfase en modelo)
    final double effectiveTotal = (data.total > 0)
        ? data.total
        : (data.items.isNotEmpty
            ? double.parse((data.subtotal - data.descuentoTotal + data.ajusteRedondeo).toStringAsFixed(2))
            : 0.0);

    _buffer.add(_alignRight);
    _writeText('${_formatTwoColumns('SUBTOTAL:', '\$${data.subtotal.toStringAsFixed(2)}', paperSize.maxChars)}\n');

    if (data.mostrarDescuentosRedondeo && data.descuentoTotal > 0) {
      _writeText('${_formatTwoColumns('DESCUENTO:', '-\$${data.descuentoTotal.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    }

    if (data.mostrarDescuentosRedondeo && data.ajusteRedondeo != 0.0) {
      final sign = data.ajusteRedondeo < 0 ? '-' : '+';
      final absVal = data.ajusteRedondeo.abs().toStringAsFixed(2);
      _writeText('${_formatTwoColumns('REDONDEO:', '$sign\$$absVal', paperSize.maxChars)}\n');
      _writeText('${_formatTwoColumns('TOTAL EFECTIVO:', '\$${effectiveTotal.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    }

    _buffer.add(_boldOn);
    _buffer.add(_doubleSize);
    _writeText('${_formatTwoColumns('TOTAL A PAGAR:', '\$${effectiveTotal.toStringAsFixed(2)}', paperSize.maxChars ~/ 2)}\n');
    _buffer.add(_normalSize);
    _buffer.add(_boldOff);

    // Importe con letra
    if (data.mostrarTotalLetra) {
      _buffer.add(_alignLeft);
      _writeText('(${numeroALetras(effectiveTotal)})\n');
    }

    _writeDivider('-');

    // 7. Formas de Pago y Cambio
    for (final p in data.pagos) {
      final label = 'Forma de pago: ${p.metodo.toUpperCase()}';
      _writeText('${_formatTwoColumns(label, '\$${p.monto.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    }
    if (data.cambio > 0) {
      _buffer.add(_boldOn);
      _writeText('${_formatTwoColumns('CAMBIO ENTREGADO:', '\$${data.cambio.toStringAsFixed(2)}', paperSize.maxChars)}\n');
      _buffer.add(_boldOff);
    }

    // 7.1 Notas / Observaciones de la Venta
    if (data.notasTicket != null && data.notasTicket!.trim().isNotEmpty) {
      _writeDivider('-');
      _buffer.add(_alignLeft);
      _buffer.add(_boldOn);
      _writeText('--- NOTAS DE LA VENTA ---\n');
      _buffer.add(_boldOff);
      for (final line in wrapText(data.notasTicket!.trim(), paperSize.maxChars)) {
        _writeText('$line\n');
      }
    }

    _writeDivider('=');

    // 8. Leyendas Comerciales y Validación (Estilo Imagen IMG-20261020-WA0002)
    _buffer.add(_alignCenter);
    if (data.garantia != null && data.garantia!.isNotEmpty) {
      _writeText('${data.garantia}\n\n');
    }
    if (data.piePagina.isNotEmpty) {
      _writeText('${data.piePagina}\n\n');
    }

    // 9. Código de Barras Folio (GS k)
    if (data.mostrarCodigoBarras) {
      _writeBarcode(data.folio);
      _writeText('\n* ${data.folio} *\n\n\n\n');
    } else {
      _writeText('\n* ${data.folio} *\n\n\n');
    }

    // 10. Corte de Papel
    _buffer.add(_cutPaper);

    return _buffer.toBytes();
  }

  static List<String> wrapText(String text, int maxWidth) {
    if (text.isEmpty) return [];
    final List<String> lines = [];
    final rawLines = text.split('\n');
    for (final raw in rawLines) {
      if (raw.length <= maxWidth) {
        lines.add(raw);
        continue;
      }
      final words = raw.split(' ');
      String current = '';
      for (final w in words) {
        if (current.isEmpty) {
          current = w;
        } else if (current.length + 1 + w.length <= maxWidth) {
          current += ' $w';
        } else {
          lines.add(current);
          current = w;
        }
      }
      if (current.isNotEmpty) {
        lines.add(current);
      }
    }
    return lines;
  }

  void _writeBarcode(String text) {
    final clean = text.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    if (clean.isEmpty) return;
    final bytes = latin1.encode(clean);
    _buffer.add([0x1D, 0x6B, 0x04]); // GS k 4 (Code 39)
    _buffer.add(bytes);
    _buffer.add([0x00]); // Null terminator
  }

  void _writeText(String text) {
    _buffer.add(latin1.encode(sanitizeTextForThermal(text)));
  }

  void _writeDivider(String char) {
    _buffer.add(_alignCenter);
    _writeText(char * paperSize.maxChars + '\n');
  }

  String _formatTwoColumns(String left, String right, int width) {
    final totalLen = left.length + right.length;
    if (totalLen >= width) {
      return '$left $right';
    }
    final spaces = width - totalLen;
    return '$left${' ' * spaces}$right';
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  /// Genera representación de texto plano para previsualización térmica en pantalla
  String buildPlainText(TicketPrintData data) {
    final sb = StringBuffer();
    final width = paperSize.maxChars;

    final double effectiveTotal = (data.total > 0)
        ? data.total
        : (data.items.isNotEmpty
            ? double.parse((data.subtotal - data.descuentoTotal + data.ajusteRedondeo).toStringAsFixed(2))
            : 0.0);

    void addCentered(String text) {
      if (text.length >= width) {
        sb.writeln(text);
      } else {
        final pad = (width - text.length) ~/ 2;
        sb.writeln('${' ' * pad}$text');
      }
    }

    if (data.mostrarNombre) {
      addCentered(data.negocioNombre);
      if (data.negocioLeyenda != null && data.negocioLeyenda!.isNotEmpty) {
        addCentered(data.negocioLeyenda!);
      }
    }

    if (data.mostrarContacto) {
      if (data.direccion != null && data.direccion!.isNotEmpty) addCentered(data.direccion!);
      if (data.rfc != null && data.rfc!.isNotEmpty) addCentered('RFC: ${data.rfc}');
      if (data.telefono != null && data.telefono!.isNotEmpty) addCentered('TEL: ${data.telefono}');
    }

    if (data.mensajeSuperior != null && data.mensajeSuperior!.isNotEmpty) {
      addCentered(data.mensajeSuperior!);
    }

    sb.writeln('=' * width);

    if (data.mostrarFolioFecha) {
      sb.writeln(_formatTwoColumns('FOLIO: ${data.folio}', _formatDate(data.fecha), width));
    }
    if (data.mostrarCliente) {
      sb.writeln('CLIENTE: ${data.clienteNombre}');
    }
    if (data.mostrarCajero) {
      sb.writeln('CAJERO: ${data.cajero} | TURNO: ${data.turnoId}');
    }
    sb.writeln('-' * width);

    sb.writeln(_formatTwoColumns('CANT  DESCRIPCION', 'TOTAL', width));
    sb.writeln('-' * width);

    for (final item in data.items) {
      final int maxNameLen = width > 14 ? width - 14 : width;
      final name = item.nombre.safePrefix(maxNameLen);
      sb.writeln(_formatTwoColumns('${item.cantidad}x $name', '\$${item.totalLinea.toStringAsFixed(2)}', width));
      if (item.etiquetaPrecio.isNotEmpty && item.etiquetaPrecio != 'Público') {
        sb.writeln('  [Nivel: ${item.etiquetaPrecio}]');
      }
      if (data.mostrarDescuentosRedondeo && item.descuentoLinea > 0) {
        sb.writeln(_formatTwoColumns('  (Desc.)', '-\$${item.descuentoLinea.toStringAsFixed(2)}', width));
      }
    }

    sb.writeln('-' * width);
    sb.writeln(_formatTwoColumns('SUBTOTAL:', '\$${data.subtotal.toStringAsFixed(2)}', width));
    if (data.mostrarDescuentosRedondeo && data.descuentoTotal > 0) {
      sb.writeln(_formatTwoColumns('DESCUENTO:', '-\$${data.descuentoTotal.toStringAsFixed(2)}', width));
    }
    if (data.mostrarDescuentosRedondeo && data.ajusteRedondeo != 0.0) {
      final sign = data.ajusteRedondeo < 0 ? '-' : '+';
      sb.writeln(_formatTwoColumns('REDONDEO:', '$sign\$${data.ajusteRedondeo.abs().toStringAsFixed(2)}', width));
    }
    sb.writeln(_formatTwoColumns('TOTAL A PAGAR:', '\$${effectiveTotal.toStringAsFixed(2)}', width));
    if (data.mostrarTotalLetra) {
      sb.writeln('(${numeroALetras(effectiveTotal)})');
    }
    sb.writeln('=' * width);

    for (final p in data.pagos) {
      sb.writeln(_formatTwoColumns('Forma de pago: ${p.metodo.toUpperCase()}', '\$${p.monto.toStringAsFixed(2)}', width));
    }
    if (data.cambio > 0) {
      sb.writeln(_formatTwoColumns('CAMBIO:', '\$${data.cambio.toStringAsFixed(2)}', width));
    }
    if (data.notasTicket != null && data.notasTicket!.trim().isNotEmpty) {
      sb.writeln('-' * width);
      sb.writeln('--- NOTAS DE LA VENTA ---');
      for (final line in wrapText(data.notasTicket!.trim(), width)) {
        sb.writeln(line);
      }
    }
    sb.writeln('=' * width);
    if (data.garantia != null && data.garantia!.isNotEmpty) {
      addCentered(data.garantia!);
    }
    if (data.piePagina.isNotEmpty) {
      addCentered(data.piePagina);
    }
    sb.writeln('');
    if (data.mostrarCodigoBarras) {
      addCentered('|| |||||| | |||||||| |||||');
    }
    addCentered('* ${data.folio} *');

    return sb.toString();
  }
}
