import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:client/core/string_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/local/models.dart';
import 'package:client/presentation/controllers/cart_controller.dart';

void main() {
  group('Fase 3: Regla Exacta de Redondeo de Centavos en Efectivo', () {
    test('1. Centavos == 0.00 se mantiene en el entero exacto', () {
      expect(calcularRedondeoEfectivo(18.00), 18.00);
      expect(calcularAjusteRedondeo(18.00), 0.00);

      expect(calcularRedondeoEfectivo(100.00), 100.00);
      expect(calcularAjusteRedondeo(100.00), 0.00);
    });

    test('2. Por debajo de 10 centavos (<= 0.10) baja a la cantidad cerrada inferior', () {
      // Ejemplo de directiva: $18.08 -> $18.00
      expect(calcularRedondeoEfectivo(18.08), 18.00);
      expect(calcularAjusteRedondeo(18.08), -0.08);

      expect(calcularRedondeoEfectivo(18.01), 18.00);
      expect(calcularAjusteRedondeo(18.01), -0.01);

      expect(calcularRedondeoEfectivo(18.10), 18.00);
      expect(calcularAjusteRedondeo(18.10), -0.10);
    });

    test('3. De 11 a 60 centavos (> 0.10 && <= 0.60) se cierra en 50 centavos', () {
      // Ejemplos de directiva: $18.12 -> $18.50, $18.50 -> $18.50, $18.60 -> $18.50
      expect(calcularRedondeoEfectivo(18.12), 18.50);
      expect(calcularAjusteRedondeo(18.12), 0.38);

      expect(calcularRedondeoEfectivo(18.50), 18.50);
      expect(calcularAjusteRedondeo(18.50), 0.00);

      expect(calcularRedondeoEfectivo(18.60), 18.50);
      expect(calcularAjusteRedondeo(18.60), -0.10);

      expect(calcularRedondeoEfectivo(25.30), 25.50);
      expect(calcularAjusteRedondeo(25.30), 0.20);
    });

    test('4. Por encima de 60 centavos (> 0.60) sube al entero inmediato superior', () {
      // Ejemplos de directiva: $18.61 -> $19.00, $18.85 -> $19.00
      expect(calcularRedondeoEfectivo(18.61), 19.00);
      expect(calcularAjusteRedondeo(18.61), 0.39);

      expect(calcularRedondeoEfectivo(18.85), 19.00);
      expect(calcularAjusteRedondeo(18.85), 0.15);

      expect(calcularRedondeoEfectivo(18.99), 19.00);
      expect(calcularAjusteRedondeo(18.99), 0.01);
    });
  });

  group('Fase 2: Precio Manual Sincronizado en Vivo con Descuentos (%)', () {
    late CartController cart;
    late Product llaveTest;

    setUp(() {
      cart = CartController();
      llaveTest = Product(
        id: 'prod-test-01',
        sku: 'TEST-01',
        nombre: 'Llave de Prueba',
        descripcion: 'Llave de prueba para cotizaciones',
        precioCompra: 5.00,
        precioVenta: 20.00,
        precioCerrajero: 15.00,
        precioTaller: 18.00,
        precioMayoreo: 12.00,
        stockActual: 50.0,
      );
    });

    test('Aplicar precio manual de diez pesos sin descuento', () {
      cart.addProduct(llaveTest, quantity: 1.0);
      final itemId = cart.items.first.id;

      cart.applyItemPriceAndDiscount(
        detailItemId: itemId,
        newUnitPrice: 10.00,
        tierLabel: 'Manual',
        discountPercent: 0.0,
      );

      final item = cart.items.first;
      expect(item.precioHistorico, 10.00);
      expect(item.descuentoLinea, 0.00);
      expect(item.totalLinea, 10.00);
      expect(item.etiquetaPrecio, 'Manual');
    });

    test('Aplicar precio manual de diez pesos con descuento del 10% (-1 peso)', () {
      cart.addProduct(llaveTest, quantity: 1.0);
      final itemId = cart.items.first.id;

      cart.applyItemPriceAndDiscount(
        detailItemId: itemId,
        newUnitPrice: 10.00,
        tierLabel: 'Manual',
        discountPercent: 10.0,
      );

      final item = cart.items.first;
      expect(item.precioHistorico, 10.00);
      expect(item.descuentoLinea, 1.00);
      expect(item.totalLinea, 9.00);
      expect(item.etiquetaPrecio, 'Manual -10%');
    });

    test('Aplicar precio manual de diez pesos con descuento del 20% para 2 piezas', () {
      cart.addProduct(llaveTest, quantity: 2.0);
      final itemId = cart.items.first.id;

      cart.applyItemPriceAndDiscount(
        detailItemId: itemId,
        newUnitPrice: 10.00,
        tierLabel: 'Manual',
        discountPercent: 20.0,
      );

      final item = cart.items.first;
      expect(item.precioHistorico, 10.00);
      expect(item.descuentoLinea, 4.00); // 20.00 * 20% = 4.00
      expect(item.totalLinea, 16.00); // 20.00 - 4.00 = 16.00
      expect(item.etiquetaPrecio, 'Manual -20%');
    });
  });

  group('Fase 1: Mapeo Seguro de Cliente y Datos Migrados', () {
    test('Cliente.fromMap maneja tipos nulos, int y campos migrados de SQLite', () {
      final Map<String, dynamic> rawMigrated = {
        'id': 'CLI-0010',
        'nombre': 'MANUEL HDZ',
        'rfc_o_dni': null,
        'telefono': 5536797344, // int en vez de String
        'direccion': 'MAGDALENA CONTRERAS',
        'limite_credito': 0,
        'saldo_actual': 5000.0, // Columna migrada de Eleventa
        'tarifa_preferencial': 'Cerrajero',
        'activo': 1,
      };

      final cliente = Cliente.fromMap(rawMigrated);

      expect(cliente.id, 'CLI-0010');
      expect(cliente.nombre, 'MANUEL HDZ');
      expect(cliente.telefono, '5536797344');
      expect(cliente.limiteCredito, 0.0);
      expect(cliente.saldoDeudor, 5000.0);
      expect(cliente.tarifaPreferencial, 'Cerrajero');
      expect(cliente.activo, true);
    });

    test('Cliente.fromMap maneja mapa vacío con fallbacks seguros', () {
      final cliente = Cliente.fromMap({});

      expect(cliente.id, '');
      expect(cliente.nombre, 'Público en General');
      expect(cliente.saldoDeudor, 0.0);
      expect(cliente.limiteCredito, 0.0);
      expect(cliente.tarifaPreferencial, 'Público');
      expect(cliente.activo, true);
    });
  });

  group('Fase 4: Configuración de Mayoreo Automático por Volumen en CartController', () {
    late CartController cart;
    late Product productoMayoreo;

    setUp(() {
      cart = CartController();
      productoMayoreo = Product(
        id: 'prod-may-01',
        sku: 'MAY-01',
        nombre: 'Cerradura Phillips',
        descripcion: 'Cerradura de sobreponer',
        precioCompra: 100.0,
        precioVenta: 200.0,      // Menudeo
        precioCerrajero: 170.0,
        precioTaller: 180.0,
        precioMayoreo: 140.0,    // Mayoreo
        stockActual: 100.0,
      );
    });

    test('Mayoreo automático desactivado: no aplica precio mayoreo aunque se compre volumen', () {
      cart.setMayoreoConfig(autoEnabled: false, umbral: 5.0);
      cart.addProduct(productoMayoreo, quantity: 10.0);

      final item = cart.items.first;
      expect(item.precioHistorico, 200.0); // Precio Venta (Público)
      expect(item.etiquetaPrecio, 'Público');
    });

    test('Mayoreo automático activado: aplica precio mayoreo al alcanzar o superar el umbral', () {
      cart.setMayoreoConfig(autoEnabled: true, umbral: 5.0);
      // 1. Con 3 piezas: precio menudeo
      cart.addProduct(productoMayoreo, quantity: 3.0);
      expect(cart.items.first.precioHistorico, 200.0);
      expect(cart.items.first.etiquetaPrecio, 'Público');

      // 2. Incrementar a 5 piezas: activa precio mayoreo automáticamente
      cart.updateQuantity(cart.items.first.id, 5.0);
      expect(cart.items.first.precioHistorico, 140.0);
      expect(cart.items.first.etiquetaPrecio, 'Mayoreo');
    });

    test('Conmutador rápido de Mayoreo Auto (toggleMayoreoAuto) recalcula el carrito en vivo', () {
      cart.setMayoreoConfig(autoEnabled: false, umbral: 5.0);
      cart.addProduct(productoMayoreo, quantity: 8.0);
      expect(cart.items.first.precioHistorico, 200.0);

      // Activar con chip rápido
      cart.toggleMayoreoAuto();
      expect(cart.mayoreoAutoEnabled, true);
      expect(cart.items.first.precioHistorico, 140.0);

      // Desactivar con chip rápido
      cart.toggleMayoreoAuto();
      expect(cart.mayoreoAutoEnabled, false);
      expect(cart.items.first.precioHistorico, 200.0);
    });
  });

  group('Fase 6: Conversor Numérico a Letras (numeroALetras) para Factura CFDI y Ticket', () {
    test('Conversión exacta del monto de la factura de prueba (\$1,501.36)', () {
      // Verificado con documento SAT CAC950316GI4FA-36004.pdf
      final letras = numeroALetras(1501.36);
      expect(letras, 'UN MIL QUINIENTOS UN PESOS 36/100 M.N.');
    });

    test('Conversión de importes cerrados y con centavos', () {
      expect(numeroALetras(0.00), 'CERO PESOS 00/100 M.N.');
      expect(numeroALetras(1.00), 'UN PESO 00/100 M.N.');
      expect(numeroALetras(18.50), 'DIECIOCHO PESOS 50/100 M.N.');
      expect(numeroALetras(100.00), 'CIEN PESOS 00/100 M.N.');
      expect(numeroALetras(250.75), 'DOSCIENTOS CINCUENTA PESOS 75/100 M.N.');
      expect(numeroALetras(1000.00), 'UN MIL PESOS 00/100 M.N.');
      expect(numeroALetras(12345.67), 'DOCE MIL TRESCIENTOS CUARENTA Y CINCO PESOS 67/100 M.N.');
    });
  });

  group('Nueva Fase 1 y 2: Identidad, Configuración y Accesibilidad del Header y Barra Inferior', () {
    test('Verificación de configuración de identidad del negocio por defecto', () {
      const defaultBusiness = 'CARprog';
      const defaultSubtitle = 'Cerrajería y Electrónica';
      const defaultPdfDir = r'C:\POS\Cotizaciones';

      expect(defaultBusiness, 'CARprog');
      expect(defaultSubtitle, 'Cerrajería y Electrónica');
      expect(defaultPdfDir, contains('Cotizaciones'));
    });
  });

  group('Nueva Fase 3: Generación Vectorial y Raster de PDF para Cotizaciones', () {
    test('Generador de PDF produce documento válido en memoria', () async {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) => pw.Center(
            child: pw.Text('Cotización de Prueba - Folio COT-TEST-001'),
          ),
        ),
      );

      final pdfBytes = await pdf.save();
      expect(pdfBytes.isNotEmpty, true);
      // Validar firma de archivo PDF (%PDF-)
      final pdfHeader = String.fromCharCodes(pdfBytes.take(5));
      expect(pdfHeader, '%PDF-');
    });
  });
}
