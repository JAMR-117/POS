import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'esc_pos_ticket_builder.dart';

enum PrinterConnectionType {
  network, // Impresora Ethernet / Wi-Fi (Puerto estándar 9100)
  usbOrFile, // Puerto local directo (ej: /dev/usb/lp0, COM1 o archivo spool)
  disabled, // Sin impresora conectada (no genera errores)
}

class PrinterConfig {
  final PrinterConnectionType type;
  final String address; // IP (ej: 192.168.1.200) o Ruta (ej: /dev/usb/lp0 o \\.\LPT1)
  final int port; // Por defecto 9100 para Raw Print Server
  final PaperSize paperSize;
  final Duration connectionTimeout;

  const PrinterConfig({
    this.type = PrinterConnectionType.network,
    this.address = '192.168.1.200',
    this.port = 9100,
    this.paperSize = PaperSize.mm80,
    this.connectionTimeout = const Duration(seconds: 2), // Fail-fast para no trabar el POS
  });
}

class PrinterService {
  PrinterConfig _config;
  late EscPosTicketBuilder _builder;

  PrinterService({PrinterConfig? config})
      : _config = config ?? const PrinterConfig() {
    _builder = EscPosTicketBuilder(paperSize: _config.paperSize);
  }

  void updateConfig(PrinterConfig newConfig) {
    _config = newConfig;
    _builder = EscPosTicketBuilder(paperSize: _config.paperSize);
  }

  /// Envía los bytes crudos a la impresora física de manera desacoplada
  Future<bool> sendRawBytes(Uint8List bytes) async {
    if (_config.type == PrinterConnectionType.disabled) {
      debugPrint('[PRINTER] Impresora deshabilitada. Omitiendo envío.');
      return true;
    }

    switch (_config.type) {
      case PrinterConnectionType.network:
        return await _sendViaSocket(bytes);
      case PrinterConnectionType.usbOrFile:
        return await _sendViaFile(bytes);
      case PrinterConnectionType.disabled:
        return true;
    }
  }

  /// Despacha la impresión de un comprobante de venta de forma totalmente asíncrona
  /// Nunca lanza excepciones hacia el hilo de UI si la impresora física está apagada
  Future<void> printSaleTicketAsync(
    TicketPrintData ticketData, {
    bool openCashDrawer = false,
  }) async {
    try {
      final bytes = _builder.buildTicket(ticketData, openCashDrawer: openCashDrawer);
      final ok = await sendRawBytes(bytes);
      if (!ok) {
        debugPrint('[PRINTER_WARN] Falló el despacho del ticket al dispositivo térmico.');
      }
    } catch (e, stack) {
      // Atrapa cualquier excepción para proteger la continuidad de la caja
      debugPrint('[PRINTER_ERROR] Error no bloqueante al imprimir ticket: $e\n$stack');
    }
  }

  Future<bool> _sendViaSocket(Uint8List bytes) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        _config.address,
        _config.port,
        timeout: _config.connectionTimeout,
      );

      socket.add(bytes);
      await socket.flush();
      return true;
    } on SocketException catch (e) {
      debugPrint('[PRINTER_SOCKET] Host inalcanzable (${_config.address}:${_config.port}): $e');
      return false;
    } on TimeoutException {
      debugPrint('[PRINTER_SOCKET] Timeout superado conectando a impresora.');
      return false;
    } catch (e) {
      debugPrint('[PRINTER_SOCKET] Error imprevisto: $e');
      return false;
    } finally {
      if (socket != null) {
        await socket.close();
        socket.destroy();
      }
    }
  }

  Future<bool> _sendViaFile(Uint8List bytes) async {
    try {
      final file = File(_config.address);
      await file.writeAsBytes(bytes, mode: FileMode.writeOnly);
      return true;
    } catch (e) {
      debugPrint('[PRINTER_FILE] Error escribiendo en puerto/archivo local (${_config.address}): $e');
      return false;
    }
  }
}