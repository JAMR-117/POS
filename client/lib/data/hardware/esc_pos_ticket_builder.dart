import 'dart:convert';
import 'dart:typed_data';
import '../local/models.dart';

enum PaperSize {
  mm58(32), // 32 caracteres por columna (estándar 58mm fuente A)
  mm80(48); // 48 caracteres por columna (estándar 80mm fuente A)

  final int maxChars;
  const PaperSize(this.maxChars);
}

/// Datos requeridos para imprimir el comprobante de venta fiscal/interno
class TicketPrintData {
  final String negocioNombre;
  final String? rfc;
  final String? direccion;
  final String? telefono;
  final String folio;
  final DateTime fecha;
  final String cajero;
  final String turnoId;
  final List<SaleDetailItem> items;
  final double subtotal;
  final double descuentoTotal;
  final double total;
  final List<PaymentMethodBreakdown> pagos;
  final double cambio;
  final String piePagina;

  const TicketPrintData({
    required this.negocioNombre,
    this.rfc,
    this.direccion,
    this.telefono,
    required this.folio,
    required this.fecha,
    required this.cajero,
    required this.turnoId,
    required this.items,
    required this.subtotal,
    this.descuentoTotal = 0.0,
    required this.total,
    required this.pagos,
    required this.cambio,
    this.piePagina = '¡Gracias por su compra!',
  });
}

/// Generador binario nativo de secuencias ESC/POS (Zero-Dependency)
class EscPosTicketBuilder {
  final PaperSize paperSize;
  final BytesBuilder _buffer = BytesBuilder();

  // Comandos estándar ESC/POS
  static const List<int> _escInit = [0x1B, 0x40]; // ESC @ (Inicializar)
  static const List<int> _alignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> _alignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> _alignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  static const List<int> _boldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> _boldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> _doubleSize = [0x1D, 0x21, 0x11]; // GS ! 0x11 (2x Alto y Ancho)
  static const List<int> _normalSize = [0x1D, 0x21, 0x00]; // GS ! 0x00 (Normal)
  static const List<int> _cutPaper = [0x1D, 0x56, 0x42, 0x00]; // GS V 66 0 (Corte parcial con avance)
  static const List<int> _openDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA]; // Pulso a cajón de dinero

  EscPosTicketBuilder({this.paperSize = PaperSize.mm80});

  Uint8List buildTicket(TicketPrintData data, {bool openCashDrawer = false}) {
    _buffer.clear();

    // 1. Inicializar
    _buffer.add(_escInit);

    // Abrir cajón si se requiere cobro en efectivo
    if (openCashDrawer) {
      _buffer.add(_openDrawer);
    }

    // 2. Encabezado del negocio
    _buffer.add(_alignCenter);
    _buffer.add(_boldOn);
    _buffer.add(_doubleSize);
    _writeText('${data.negocioNombre}\n');
    _buffer.add(_normalSize);
    _buffer.add(_boldOff);

    if (data.rfc != null && data.rfc!.isNotEmpty) {
      _writeText('RFC: ${data.rfc}\n');
    }
    if (data.direccion != null && data.direccion!.isNotEmpty) {
      _writeText('${data.direccion}\n');
    }
    if (data.telefono != null && data.telefono!.isNotEmpty) {
      _writeText('TEL: ${data.telefono}\n');
    }

    _writeDivider('=');

    // 3. Metadatos de la Venta
    _buffer.add(_alignLeft);
    _writeText('FOLIO: ${data.folio}\n');
    _writeText('FECHA: ${_formatDate(data.fecha)}\n');
    _writeText('CAJERO: ${data.cajero} | TURNO: ${data.turnoId.substring(0, data.turnoId.length > 8 ? 8 : data.turnoId.length)}\n');

    _writeDivider('-');

    // 4. Cabecera de Partidas
    if (paperSize == PaperSize.mm80) {
      _buffer.add(_boldOn);
      _writeText('${_formatTwoColumns('CANT  DESCRIPCIÓN', 'TOTAL', paperSize.maxChars)}\n');
      _buffer.add(_boldOff);
    } else {
      _buffer.add(_boldOn);
      _writeText('${_formatTwoColumns('CANT DESCRIPCIÓN', 'IMPORTE', paperSize.maxChars)}\n');
      _buffer.add(_boldOff);
    }

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

      if (item.descuentoLinea > 0) {
        _writeText('${_formatTwoColumns('  (Desc.)', '-\$${item.descuentoLinea.toStringAsFixed(2)}', paperSize.maxChars)}\n');
      }
    }

    _writeDivider('-');

    // 6. Totales y Liquidación
    _buffer.add(_alignRight);
    _writeText('${_formatTwoColumns('SUBTOTAL:', '\$${data.subtotal.toStringAsFixed(2)}', paperSize.maxChars)}\n');

    if (data.descuentoTotal > 0) {
      _writeText('${_formatTwoColumns('DESCUENTO:', '-\$${data.descuentoTotal.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    }

    _buffer.add(_boldOn);
    _buffer.add(_doubleSize);
    _writeText('${_formatTwoColumns('TOTAL:', '\$${data.total.toStringAsFixed(2)}', paperSize.maxChars ~/ (paperSize == PaperSize.mm80 ? 2 : 2))}\n');
    _buffer.add(_normalSize);
    _buffer.add(_boldOff);

    _writeDivider('-');

    // 7. Formas de Pago y Cambio
    _buffer.add(_alignLeft);
    for (final p in data.pagos) {
      final label = 'PAGO (${p.metodo.toUpperCase()}):';
      _writeText('${_formatTwoColumns(label, '\$${p.monto.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    }
    _buffer.add(_boldOn);
    _writeText('${_formatTwoColumns('CAMBIO ENTREGADO:', '\$${data.cambio.toStringAsFixed(2)}', paperSize.maxChars)}\n');
    _buffer.add(_boldOff);

    _writeDivider('=');

    // 8. Pie de Página y Salto de Papel
    _buffer.add(_alignCenter);
    _writeText('${data.piePagina}\n');
    _writeText('Impreso en terminal Offline-First POS\n\n\n\n'); // Avance para guillotine

    // 9. Corte de Papel
    _buffer.add(_cutPaper);

    return _buffer.toBytes();
  }

  void _writeText(String text) {
    // Codificación Latin-1 / ISO-8859-1 para soporte directo de caracteres especiales y acentos en ESC/POS
    _buffer.add(latin1.encode(text));
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
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}