import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../data/local/models.dart';

class QuoteDialog extends StatelessWidget {
  final List<SaleDetailItem> items;
  final double subtotal;
  final double descuentoTotal;
  final double total;
  final String nombreNegocio;
  final String telefonoContacto;
  final String emailContacto;
  final String clienteNombre;

  const QuoteDialog({
    super.key,
    required this.items,
    required this.subtotal,
    required this.descuentoTotal,
    required this.total,
    this.nombreNegocio = 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ',
    this.telefonoContacto = '+52 (55) 1234-5678',
    this.emailContacto = 'contacto@cerrajeriapos.com',
    this.clienteNombre = 'Público en General',
  });

  static Future<void> show(
    BuildContext context, {
    required List<SaleDetailItem> items,
    required double subtotal,
    required double descuentoTotal,
    required double total,
    String? nombreNegocio,
    String? clienteNombre,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => QuoteDialog(
        items: items,
        subtotal: subtotal,
        descuentoTotal: descuentoTotal,
        total: total,
        nombreNegocio: nombreNegocio ?? 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ',
        clienteNombre: clienteNombre ?? 'Público en General',
      ),
    );
  }

  String _generatePlainTextTicket(String folio, String fechaStr) {
    final buffer = StringBuffer();
    buffer.writeln('====================================');
    buffer.writeln('       $nombreNegocio');
    buffer.writeln('  TEL/WA: $telefonoContacto');
    buffer.writeln('  EMAIL:  $emailContacto');
    buffer.writeln('====================================');
    buffer.writeln('*** COTIZACIÓN INFORMATIVA ***');
    buffer.writeln('(Precios sujetos a cambio)');
    buffer.writeln('------------------------------------');
    buffer.writeln('Folio:   $folio');
    buffer.writeln('Fecha:   $fechaStr');
    buffer.writeln('Cliente: $clienteNombre');
    buffer.writeln('------------------------------------');
    buffer.writeln('CANT.  DESCRIPCIÓN          TOTAL');
    buffer.writeln('------------------------------------');

    for (final it in items) {
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
    buffer.writeln('SUBTOTAL:         \$${subtotal.toStringAsFixed(2)}');
    if (descuentoTotal > 0) {
      buffer.writeln('DESCUENTO:       -\$${descuentoTotal.toStringAsFixed(2)}');
    }
    buffer.writeln('TOTAL ESTIMADO:   \$${total.toStringAsFixed(2)}');
    buffer.writeln('====================================');
    buffer.writeln('¡Agradecemos su preferencia!');
    buffer.writeln('* Esta cotización no reserva inventario *');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final folio = 'COT-${now.millisecondsSinceEpoch.toString().substring(7)}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 650),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cabecera Modal
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1F4E79),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.request_quote_outlined, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ticket Digital de Cotización',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Cuerpo del Ticket Digital
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Encabezado
                      Text(
                        nombreNegocio,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F4E79),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'WhatsApp: $telefonoContacto | Email: $emailContacto',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),

                      // Leyenda Informativa
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Color(0xFF795548),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Folio y Fecha
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Folio: $folio', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(fechaStr, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Cliente: $clienteNombre', style: const TextStyle(fontSize: 13)),
                      ),
                      const Divider(height: 20, thickness: 1),

                      // Tabla de Partidas
                      const Row(
                        children: [
                          SizedBox(width: 50, child: Text('CANT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(child: Text('PRODUCTO / SERVICIO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 70, child: Text('P. UNIT', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 80, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                      const Divider(height: 12, thickness: 1),

                      ...items.map((it) {
                        final isGranel = (it.cantidad % 1 != 0);
                        final qtyStr = it.cantidad.toStringAsFixed(isGranel ? 3 : 0);
                        final displayName = it.nombre.isNotEmpty ? it.nombre : it.descripcion;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 50,
                                child: Text(qtyStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              ),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '\$${it.precioHistorico.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '\$${it.totalLinea.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      const Divider(height: 20, thickness: 1),

                      // Totales
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subtotal:', style: TextStyle(fontSize: 13)),
                          Text('\$${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                      if (descuentoTotal > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Descuento:', style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32))),
                            Text('-\$${descuentoTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Color(0xFF2E7D32))),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F4E79),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL COTIZACIÓN:',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '* Precios en Moneda Nacional. Validez por 7 días naturales.',
                        style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Barra Inferior de Acciones
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar Texto (WhatsApp / Mail)'),
                    onPressed: () {
                      final plainText = _generatePlainTextTicket(folio, fechaStr);
                      Clipboard.setData(ClipboardData(text: plainText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cotización copiada al portapapeles.'),
                          backgroundColor: Color(0xFF2E7D32),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
