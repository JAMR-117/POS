import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/local/models.dart';
import 'package:client/presentation/controllers/cart_controller.dart';
import 'package:client/data/hardware/esc_pos_ticket_builder.dart';

void main() {
  group('ISO/IEC 25010 - CartController & Services QA Test Suite', () {
    late CartController cart;
    late Product llaveAlba;
    late Product servicioDuplicado;
    late Product pilaEnergizer;

    setUp(() {
      cart = CartController();

      llaveAlba = Product(
        id: 'prod-llave-alba-r52',
        sku: 'R-52',
        nombre: 'Llave Virgen Alba R52',
        descripcion: 'Llave latón 5 pernos compatible Phillips',
        marca: 'Alba',
        ubicacion: 'Gaveta A-12',
        departamento: 'Residencial',
        precioCompra: 4.00,
        precioVenta: 15.00,
        precioCerrajero: 10.00,
        precioTaller: 12.00,
        precioMayoreo: 8.00,
        cantidadMayoreo: 10.0,
        stockActual: 20.0,
        stockMinimo: 5.0,
      );

      servicioDuplicado = Product(
        id: 'serv-dup-residencial',
        sku: 'SERV-DUP-RES',
        nombre: 'Duplicado de Llave Residencial',
        descripcion: 'Corte y duplicado llave tradicional de casa',
        marca: 'Servicio',
        departamento: 'Residencial',
        precioCompra: 0.0,
        precioVenta: 20.00,
        precioCerrajero: 15.00,
        precioTaller: 18.00,
        stockActual: 9999.0,
        esServicio: true,
      );

      pilaEnergizer = Product(
        id: 'prod-pila-cr2032',
        sku: 'CR-2032',
        nombre: 'Pila Botón CR-2032 Energizer',
        descripcion: 'Pila de litio 3V para control o reloj',
        marca: 'Energizer',
        ubicacion: 'Mostrador Gaveta B-01',
        departamento: 'Pilas y Baterías',
        precioCompra: 12.00,
        precioVenta: 35.00,
        precioCerrajero: 25.00,
        stockActual: 3.0,
        stockMinimo: 5.0,
      );
    });

    test('Asignación de niveles de precio (Público, Cerrajero, Taller, Mayoreo) y recálculo automático', () {
      cart.addProduct(llaveAlba, quantity: 2);
      expect(cart.items.length, 1);
      final item = cart.items.first;

      // Precio por defecto: Público ($15.00 c/u -> $30.00)
      expect(item.precioHistorico, 15.00);
      expect(item.totalLinea, 30.00);
      expect(cart.total, 30.00);

      // Cambiar a Cerrajero ($10.00 c/u -> $20.00)
      cart.changeItemPriceTier(item.id, 10.00, 'Cerrajero');
      final updatedItemCerrajero = cart.items.first;
      expect(updatedItemCerrajero.precioHistorico, 10.00);
      expect(updatedItemCerrajero.etiquetaPrecio, 'Cerrajero');
      expect(updatedItemCerrajero.totalLinea, 20.00);
      expect(cart.total, 20.00);

      // Cambiar a Taller ($12.00 c/u -> $24.00)
      cart.changeItemPriceTier(item.id, 12.00, 'Taller');
      final updatedItemTaller = cart.items.first;
      expect(updatedItemTaller.precioHistorico, 12.00);
      expect(updatedItemTaller.etiquetaPrecio, 'Taller');
      expect(updatedItemTaller.totalLinea, 24.00);
      expect(cart.total, 24.00);

      // Cambiar a Mayoreo ($8.00 c/u -> $16.00)
      cart.changeItemPriceTier(item.id, 8.00, 'Mayoreo');
      final updatedItemMayoreo = cart.items.first;
      expect(updatedItemMayoreo.precioHistorico, 8.00);
      expect(updatedItemMayoreo.etiquetaPrecio, 'Mayoreo');
      expect(updatedItemMayoreo.totalLinea, 16.00);
      expect(cart.total, 16.00);

      // Establecer precio personalizado manual
      cart.changeItemPriceTier(item.id, 9.50, 'Personalizado');
      final updatedItemManual = cart.items.first;
      expect(updatedItemManual.precioHistorico, 9.50);
      expect(updatedItemManual.etiquetaPrecio, 'Personalizado');
      expect(updatedItemManual.totalLinea, 19.00);
      expect(cart.total, 19.00);
    });

    test('Duplicado con insumo dinámico: vincula y descuenta insumo físico en BOM', () {
      // Agregar servicio de duplicado vinculado a la llave Alba R52
      cart.addDynamicServiceItem(
        service: servicioDuplicado,
        insumo: llaveAlba,
        precioCobrado: 20.00,
        etiquetaPrecio: 'Público',
        cantidadInsumoConsumida: 1.0,
      );

      expect(cart.items.length, 1);
      final serviceItem = cart.items.first;
      expect(serviceItem.esServicio, true);
      expect(serviceItem.hasDynamicInsumo, true);
      expect(serviceItem.insumoUtilizadoId, llaveAlba.id);
      expect(serviceItem.cantidadInsumoConsumida, 1.0);
      expect(serviceItem.precioHistorico, 20.00);
      expect(serviceItem.costoHistorico, llaveAlba.precioCompra);

      // Modificación en vivo de cantidad de servicio y de insumo consumido
      cart.updateServiceLine(
        detailItemId: serviceItem.id,
        newUnitPrice: 22.00,
        newQuantity: 2.0,
        newCantidadInsumoConsumida: 2.0,
      );

      final editedItem = cart.items.first;
      expect(editedItem.cantidad, 2.0);
      expect(editedItem.precioHistorico, 22.00);
      expect(editedItem.cantidadInsumoConsumida, 2.0);
      expect(editedItem.totalLinea, 44.00);
      expect(cart.total, 44.00);
    });

    test('Validación de Stock Insuficiente: Soft-stop y detección de agotamiento', () {
      // Agregar pila con stock disponible = 3
      cart.addProduct(pilaEnergizer, quantity: 2);
      expect(cart.items.length, 1);
      expect(cart.items.first.stockDisponible, 3.0);

      // Modificar cantidad en carrito superando stock disponible
      cart.updateQuantity(cart.items.first.id, 5); // Solicita 5 de 3 existentes
      final itemExcedido = cart.items.first;
      expect(itemExcedido.cantidad, 5.0);

      // El sistema preserva la cantidad solicitada para permitir al cajero autorizar o ajustar
      expect(itemExcedido.stockDisponible, 3.0);
      expect(itemExcedido.cantidad > itemExcedido.stockDisponible, true);

      // La partida puede reducirse nuevamente o cancelarse
      cart.removeItem(itemExcedido.id);
      expect(cart.isEmpty, true);
      expect(cart.total, 0.0);
    });

    test('Unified Pricing Popover: applyItemPriceAndDiscount con Nivel Cerrajero y 10% Descuento', () {
      cart.addProduct(llaveAlba, quantity: 2);
      final item = cart.items.first;

      // Aplicar nivel Cerrajero ($10.00) con 10% de descuento (-$1.00/u -> $9.00/u -> total $18.00)
      cart.applyItemPriceAndDiscount(
        detailItemId: item.id,
        newUnitPrice: 10.00,
        tierLabel: 'Cerrajero',
        discountPercent: 10.0,
      );

      final updated = cart.items.first;
      expect(updated.precioHistorico, 10.00);
      expect(updated.descuentoLinea, 2.00); // $1.00 x 2 = $2.00
      expect(updated.totalLinea, 18.00);
      expect(updated.etiquetaPrecio, 'Cerrajero -10%');
      expect(cart.total, 18.00);
    });

    test('Unified Pricing Popover: applyGlobalPriceAndDiscount masivo a todo el carrito', () {
      cart.addProduct(llaveAlba, quantity: 2); // Público $15.00 c/u, Cerrajero $10.00
      cart.addProduct(pilaEnergizer, quantity: 1); // Público $35.00, Cerrajero $25.00

      // Aplicar nivel global Cerrajero con 5% de descuento adicional
      cart.cacheProduct(llaveAlba);
      cart.cacheProduct(pilaEnergizer);
      cart.applyGlobalPriceAndDiscount(tierLabel: 'Cerrajero', discountPercent: 5.0);

      expect(cart.currentGlobalTier, 'Cerrajero');
      final item1 = cart.items[0];
      final item2 = cart.items[1];

      // Llave Alba: base $10.00 x 2 = $20.00, 5% desc = $1.00, total = $19.00
      expect(item1.precioHistorico, 10.00);
      expect(item1.descuentoLinea, 1.00);
      expect(item1.totalLinea, 19.00);
      expect(item1.etiquetaPrecio, 'Cerrajero -5%');

      // Pila Energizer: base $25.00 x 1 = $25.00, 5% desc = $1.25, total = $23.75
      expect(item2.precioHistorico, 25.00);
      expect(item2.descuentoLinea, 1.25);
      expect(item2.totalLinea, 23.75);
      expect(item2.etiquetaPrecio, 'Cerrajero -5%');

      expect(cart.total, 42.75);
    });

    test('Fase 4 - Redondeo en Efectivo: ajusteRedondeo al peso más cercano', () {
      // Simulación de cálculo de redondeo con centavos
      const double rawTotal1 = 123.40;
      final double rounded1 = rawTotal1.roundToDouble(); // 123.00
      final double ajuste1 = double.parse((rounded1 - rawTotal1).toStringAsFixed(2)); // -0.40
      expect(rounded1, 123.00);
      expect(ajuste1, -0.40);

      const double rawTotal2 = 123.60;
      final double rounded2 = rawTotal2.roundToDouble(); // 124.00
      final double ajuste2 = double.parse((rounded2 - rawTotal2).toStringAsFixed(2)); // +0.40
      expect(rounded2, 124.00);
      expect(ajuste2, 0.40);

      // Verificación del cambio sobre el monto redondeado
      const double pagoEfectivo = 200.00;
      final double cambio = pagoEfectivo - rounded1; // 200 - 123 = 77
      expect(cambio, 77.00);
    });

    test('Fase 4 - EscPosTicketBuilder imprime línea de REDONDEO y TOTAL EFECTIVO', () {
      final builder = EscPosTicketBuilder();
      final printData = TicketPrintData(
        negocioNombre: 'Cerrajería El Chango',
        folio: 'TK-12345',
        fecha: DateTime.now(),
        cajero: 'Cajero Principal',
        turnoId: 'TURNO-1',
        items: [
          SaleDetailItem(
            id: 'item-1',
            productoId: 'prod-1',
            nombre: 'Duplicado Forja',
            descripcion: 'Duplicado Forja',
            cantidad: 1.0,
            precioHistorico: 123.40,
            totalLinea: 123.40,
          ),
        ],
        subtotal: 123.40,
        total: 123.00,
        ajusteRedondeo: -0.40,
        pagos: [
          PaymentMethodBreakdown(metodo: 'efectivo', monto: 123.00),
        ],
        cambio: 77.00,
      );

      final bytes = builder.buildTicket(printData);
      expect(bytes.isNotEmpty, true);
      final textTicket = String.fromCharCodes(bytes);
      expect(textTicket.contains('REDONDEO:'), true);
      expect(textTicket.contains(r'-$0.40'), true);
      expect(textTicket.contains('TOTAL EFECTIVO:'), true);
    });
  });
}
