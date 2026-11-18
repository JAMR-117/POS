import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/local/business_config.dart';
import 'package:client/data/local/models.dart';
import 'package:client/data/hardware/esc_pos_ticket_builder.dart';
import 'package:client/data/repositories/shift_repository.dart';
import 'package:client/data/repositories/sales_repository.dart';
import 'package:client/presentation/controllers/cart_controller.dart';

void main() {
  group('Fase 1: BusinessConfig Single Source of Truth', () {
    test('Valores por defecto de BusinessConfig reflejan identidad comercial', () {
      const config = BusinessConfig();
      expect(config.negocioNombre, 'CARprog');
      expect(config.ticketAnchoPapel, '80mm');
      expect(config.ticketMostrarLogo, isTrue);
      expect(config.ticketMostrarNombre, isTrue);
      expect(config.ticketMostrarContacto, isTrue);
      expect(config.ticketMostrarDescuentosRedondeo, isTrue);
      expect(config.ticketMostrarTotalLetra, isTrue);
      expect(config.rutaGuardadoPdf, contains('Cotizaciones'));
    });

    test('copyWith preserva campos no modificados y actualiza campos objetivo', () {
      const original = BusinessConfig();
      final updated = original.copyWith(
        negocioNombre: 'Cerrajería Master',
        ticketAnchoPapel: '58mm',
        ticketMostrarTotalLetra: false,
      );

      expect(updated.negocioNombre, 'Cerrajería Master');
      expect(updated.ticketAnchoPapel, '58mm');
      expect(updated.ticketMostrarTotalLetra, isFalse);
      expect(updated.negocioRfc, original.negocioRfc);
      expect(updated.ticketMostrarNombre, isTrue);
    });

    test('BusinessConfig.notifier reacciona a cambios', () {
      var notified = false;
      void listener() {
        notified = true;
      }

      BusinessConfig.notifier.addListener(listener);
      final nuevo = BusinessConfig.current.copyWith(negocioNombre: 'CARprog Express');
      BusinessConfig.current = nuevo;
      BusinessConfig.notifier.value = nuevo;

      expect(notified, isTrue);
      expect(BusinessConfig.current.negocioNombre, 'CARprog Express');
      BusinessConfig.notifier.removeListener(listener);
    });
  });

  group('Fase 2: EscPosTicketBuilder con Plantilla Personalizable', () {
    final sampleItems = [
      SaleDetailItem(
        id: '1',
        productoId: 'p1',
        nombre: 'Llave Ford con Chip',
        descripcion: 'Duplicado de llave',
        cantidad: 2.0,
        precioHistorico: 450.0,
        costoHistorico: 150.0,
        descuentoLinea: 50.0,
        totalLinea: 850.0,
        etiquetaPrecio: 'Mayoreo',
      ),
    ];

    test('buildPlainText incluye datos cuando las banderas están activas', () {
      final builder80 = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      final data = TicketPrintData(
        negocioNombre: 'CARprog',
        negocioLeyenda: 'Cerrajería Automotriz',
        rfc: 'XAXX010101000',
        direccion: 'Av. Tecnológico #405',
        telefono: '555-123-4567',
        folio: 'TK-1001',
        fecha: DateTime(2026, 11, 13, 14, 30),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        clienteNombre: 'Taller Hermanos Gómez',
        items: sampleItems,
        subtotal: 900.0,
        descuentoTotal: 50.0,
        total: 850.0,
        ajusteRedondeo: 0.0,
        pagos: [PaymentMethodBreakdown(metodo: 'Efectivo', monto: 850.0)],
        cambio: 0.0,
        garantia: 'Garantía de 30 días.',
        piePagina: '¡Gracias por su compra!',
        mostrarLogo: true,
        mostrarNombre: true,
        mostrarContacto: true,
        mostrarFolioFecha: true,
        mostrarCajero: true,
        mostrarCliente: true,
        mostrarDescuentosRedondeo: true,
        mostrarTotalLetra: true,
      );

      final text = builder80.buildPlainText(data);
      expect(text, contains('CARprog'));
      expect(text, contains('Cerrajería Automotriz'));
      expect(text, contains('XAXX010101000'));
      expect(text, contains('TK-1001'));
      expect(text, contains('Taller Hermanos Gómez'));
      expect(text, contains('cajero1'));
      expect(text, contains('DESCUENTO:'));
      expect(text, contains('OCHOCIENTOS CINCUENTA PESOS'));
      expect(text, contains('Garantía de 30 días.'));
    });

    test('buildPlainText oculta secciones cuando las banderas están desactivadas', () {
      final builder80 = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      final data = TicketPrintData(
        negocioNombre: 'CARprog',
        negocioLeyenda: 'Cerrajería Automotriz',
        rfc: 'XAXX010101000',
        folio: 'TK-1001',
        fecha: DateTime(2026, 11, 13, 14, 30),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        clienteNombre: 'Taller Hermanos Gómez',
        items: sampleItems,
        subtotal: 900.0,
        descuentoTotal: 50.0,
        total: 850.0,
        ajusteRedondeo: 0.0,
        pagos: [PaymentMethodBreakdown(metodo: 'Efectivo', monto: 850.0)],
        cambio: 0.0,
        mostrarNombre: false,
        mostrarContacto: false,
        mostrarFolioFecha: false,
        mostrarCajero: false,
        mostrarCliente: false,
        mostrarDescuentosRedondeo: false,
        mostrarTotalLetra: false,
      );

      final text = builder80.buildPlainText(data);
      expect(text.contains('CARprog'), isFalse);
      expect(text.contains('XAXX010101000'), isFalse);
      expect(text.contains('FOLIO:'), isFalse);
      expect(text.contains('CAJERO:'), isFalse);
      expect(text.contains('CLIENTE:'), isFalse);
      expect(text.contains('DESCUENTO:'), isFalse);
      expect(text.contains('PESOS'), isFalse);
      // Pero el total siempre se imprime
      expect(text, contains('TOTAL A PAGAR:'));
    });

    test('Ancho de papel de 58mm formatea a 32 columnas y 80mm a 48 columnas', () {
      final b58 = EscPosTicketBuilder(paperSize: PaperSize.mm58);
      final b80 = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      expect(b58.paperSize.maxChars, 32);
      expect(b80.paperSize.maxChars, 48);
    });
  });

  group('Fase 4: Redondeo en Efectivo y Total a Cobrar', () {
    test('calcularRedondeoEfectivo redondea según regla estipulada', () {
      // 1. Entero exacto
      expect(calcularRedondeoEfectivo(150.00), 150.00);
      // 2. <= 0.10 baja al entero inferior
      expect(calcularRedondeoEfectivo(150.08), 150.00);
      expect(calcularRedondeoEfectivo(150.10), 150.00);
      // 3. > 0.10 y <= 0.60 cierra en 0.50
      expect(calcularRedondeoEfectivo(150.11), 150.50);
      expect(calcularRedondeoEfectivo(150.35), 150.50);
      expect(calcularRedondeoEfectivo(150.60), 150.50);
      // 4. > 0.60 sube al entero superior
      expect(calcularRedondeoEfectivo(150.61), 151.00);
      expect(calcularRedondeoEfectivo(150.95), 151.00);
    });
  });

  group('Nuevas Fases 1 a 5: Auditoría, Térmica, Fallbacks y Resumen', () {
    test('Fase 1: sanitizeTextForThermal remueve acentos y caracteres especiales sin basura', () {
      const input = 'Cerrajería Automotriz: Llave con chip en Niño Perdido ¡Oferta! ¿Desea factura?';
      final sanitized = EscPosTicketBuilder.sanitizeTextForThermal(input);
      expect(sanitized.contains('í'), isFalse);
      expect(sanitized.contains('ñ'), isFalse);
      expect(sanitized.contains('¿'), isFalse);
      expect(sanitized.contains('¡'), isFalse);
      expect(sanitized, contains('Nino'));
      expect(sanitized, contains('Cerrajería Automotriz'.replaceAll('í', 'i')));
    });

    test('Fase 2: Fallback de TOTAL A PAGAR cuando data.total viene en 0.00', () {
      final builder80 = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      final data = TicketPrintData(
        negocioNombre: 'CARprog',
        folio: 'TK-ZERO-TEST',
        fecha: DateTime.now(),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        items: [
          SaleDetailItem(
            id: '1',
            productoId: 'p1',
            nombre: 'Control Remoto Alarma',
            descripcion: 'Control para auto',
            cantidad: 1.0,
            precioHistorico: 500.0,
            costoHistorico: 200.0,
            totalLinea: 500.0,
          ),
        ],
        subtotal: 500.0,
        descuentoTotal: 50.0,
        ajusteRedondeo: 0.0,
        total: 0.0, // Simulación de carrito vaciado previamente
        pagos: [PaymentMethodBreakdown(metodo: 'Efectivo', monto: 450.0)],
        cambio: 0.0,
      );

      final text = builder80.buildPlainText(data);
      expect(text, contains('TOTAL A PAGAR:'));
      expect(text, contains('450.00'));
      expect(text, isNot(contains('\$0.00')));
    });

    test('Fase 3: ShiftSummary.isConsolidatedDay identifica cortes consolidados', () {
      const summaryTurno = ShiftSummary(
        shiftId: 'SHIFT-UUID-1234',
        montoInicial: 500.0,
        ventasEfectivo: 200.0,
        ventasTarjeta: 100.0,
        ventasTransferencia: 0.0,
        totalVentas: 300.0,
        totalTickets: 2,
        totalEfectivoEsperado: 700.0,
      );
      expect(summaryTurno.isConsolidatedDay, isFalse);

      const summaryDia = ShiftSummary(
        shiftId: 'DIA-2026-11-13',
        montoInicial: 0.0,
        ventasEfectivo: 1500.0,
        ventasTarjeta: 800.0,
        ventasTransferencia: 200.0,
        totalVentas: 2500.0,
        totalTickets: 12,
        totalEfectivoEsperado: 1500.0,
      );
      expect(summaryDia.isConsolidatedDay, isTrue);
    });

    test('Fase 4: Configuración y renderizado condicional de Código de Barras', () {
      const configDefault = BusinessConfig();
      expect(configDefault.ticketMostrarCodigoBarras, isTrue);

      final configDisabled = configDefault.copyWith(ticketMostrarCodigoBarras: false);
      expect(configDisabled.ticketMostrarCodigoBarras, isFalse);

      final builder = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      final dataWithBarcode = TicketPrintData(
        negocioNombre: 'CARprog',
        folio: 'TK-BC-1',
        fecha: DateTime.now(),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        items: [],
        subtotal: 100.0,
        total: 100.0,
        pagos: [],
        cambio: 0.0,
        mostrarCodigoBarras: true,
      );
      expect(builder.buildPlainText(dataWithBarcode), contains('|| |||||| | |||||||| |||||'));

      final dataWithoutBarcode = TicketPrintData(
        negocioNombre: 'CARprog',
        folio: 'TK-BC-2',
        fecha: DateTime.now(),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        items: [],
        subtotal: 100.0,
        total: 100.0,
        pagos: [],
        cambio: 0.0,
        mostrarCodigoBarras: false,
      );
      expect(builder.buildPlainText(dataWithoutBarcode).contains('|| |||||| | |||||||| |||||'), isFalse);
    });

    test('Fase 5: SaleRecord getters y resolución de método de pago principal', () {
      final saleEfectivo = SaleRecord(
        id: 's1',
        folioTicket: 'TK-01',
        total: 150.0,
        fechaVenta: DateTime(2026, 11, 13, 10, 0),
        estatus: 'completado',
        pagosDesglose: [{'metodo': 'efectivo', 'monto': 150.0}],
      );
      expect(saleEfectivo.primaryPaymentMethod, 'Efectivo');
      expect(saleEfectivo.isCancelado, isFalse);

      final saleCancelado = SaleRecord(
        id: 's2',
        folioTicket: 'TK-02',
        total: 300.0,
        fechaVenta: DateTime(2026, 11, 13, 11, 0),
        estatus: 'cancelado',
        pagosDesglose: [{'metodo': 'tarjeta', 'monto': 300.0}],
      );
      expect(saleCancelado.primaryPaymentMethod, 'Tarjeta');
      expect(saleCancelado.isCancelado, isTrue);

      final saleMixto = SaleRecord(
        id: 's3',
        folioTicket: 'TK-03',
        total: 500.0,
        fechaVenta: DateTime(2026, 11, 13, 12, 0),
        estatus: 'completado',
        pagosDesglose: [
          {'metodo': 'efectivo', 'monto': 200.0},
          {'metodo': 'tarjeta', 'monto': 300.0},
        ],
      );
      expect(saleMixto.primaryPaymentMethod, 'Mixto');
    });

    test('Fase 6: Notas en Ticket y Sanitización Word Wrap', () {
      final builder = EscPosTicketBuilder(paperSize: PaperSize.mm80);
      final dataWithNotes = TicketPrintData(
        negocioNombre: 'CARprog',
        folio: 'TK-NOTE-1',
        fecha: DateTime.now(),
        cajero: 'cajero1',
        turnoId: 'TURNO-01',
        items: [],
        subtotal: 150.0,
        total: 150.0,
        pagos: [],
        cambio: 0.0,
        notasTicket: 'Entregar duplicado en mostrador 2. Garantía válida por 30 días.',
        fontFamily: 'Fuente B',
      );

      final plain = builder.buildPlainText(dataWithNotes);
      expect(plain, contains('--- NOTAS DE LA VENTA ---'));
      expect(plain, contains('Entregar duplicado en mostrador 2.'));

      final binary = builder.buildTicket(dataWithNotes);
      expect(binary.isNotEmpty, isTrue);

      final wrapped = EscPosTicketBuilder.wrapText('PalabraMuyLargaQueNoCabeEnUnaLinea OcupandoEspacio', 20);
      expect(wrapped.isNotEmpty, isTrue);
    });

    test('Fase 7: BusinessConfig soporte para crédito global y tipografía', () {
      const cfg = BusinessConfig();
      expect(cfg.creditoClientesHabilitado, isTrue);
      expect(cfg.ticketFontFamily, 'Fuente A');
      expect(cfg.ticketFontSize, 'Normal');

      final mod = cfg.copyWith(
        creditoClientesHabilitado: false,
        ticketFontFamily: 'Fuente B',
        ticketFontSize: 'Grande',
      );
      expect(mod.creditoClientesHabilitado, isFalse);
      expect(mod.ticketFontFamily, 'Fuente B');
      expect(mod.ticketFontSize, 'Grande');
    });
  });
}
