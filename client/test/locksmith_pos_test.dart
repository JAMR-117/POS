import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/local/models.dart';
import 'package:client/presentation/controllers/cart_controller.dart';

void main() {
  group('Modelos Especializados de Cerrajería', () {
    test('Product serializa y deserializa campos de cerrajería y BOM', () {
      final product = Product(
        id: 'prod-alba-r52',
        codigoBarras: '750000000052',
        sku: 'R-52',
        nombre: 'Llave Virgen R-52',
        descripcion: 'Compatible con cerraduras Phillips mod. 715, 5 pernos, latón',
        marca: 'Alba',
        codigoEquivalencia: 'EQ-PHI52',
        ubicacion: 'Tablero 1 - Gancho 14',
        precioCompra: 3.50,
        precioVenta: 15.00,
        porcentajeImpuesto: 0.16,
        departamento: 'Llaves Tradicionales',
        stockActual: 150.0,
        esAGranel: false,
        cantidadMayoreo: 10.0,
        precioMayoreo: 10.00,
        esServicio: false,
        insumoVinculadoId: null,
        cantidadInsumo: 1.0,
      );

      final map = product.toMap();
      expect(map['nombre'], 'Llave Virgen R-52');
      expect(map['codigo_equivalencia'], 'EQ-PHI52');
      expect(map['ubicacion'], 'Tablero 1 - Gancho 14');
      expect(map['cantidad_mayoreo'], 10.0);
      expect(map['precio_mayoreo'], 10.00);

      final fromMapProd = Product.fromMap(map);
      expect(fromMapProd.id, 'prod-alba-r52');
      expect(fromMapProd.sku, 'R-52');
      expect(fromMapProd.codigoEquivalencia, 'EQ-PHI52');
      expect(fromMapProd.hasWholesalePrice, true);
      expect(fromMapProd.isServiceWithInput, false);
    });

    test('Servicio con insumo vinculado identifica correctamente BOM ligero', () {
      final service = Product(
        id: 'serv-dup-r52',
        sku: 'SERV-R52',
        nombre: 'Servicio Duplicado Llave Phillips R-52',
        descripcion: 'Corte y duplicado perfil Phillips R52',
        marca: 'Taller',
        precioCompra: 4.50,
        precioVenta: 35.00,
        stockActual: 999.0,
        esServicio: true,
        insumoVinculadoId: 'prod-alba-r52',
        cantidadInsumo: 1.0,
      );

      expect(service.esServicio, true);
      expect(service.isServiceWithInput, true);
      expect(service.insumoVinculadoId, 'prod-alba-r52');
      expect(service.cantidadInsumo, 1.0);
    });
  });

  group('CartController - Reglas de Negocio Cerrajería y Mayoreo', () {
    late CartController cart;
    late Product llaveAlba;

    setUp(() {
      cart = CartController();
      llaveAlba = Product(
        id: 'prod-alba-r52',
        sku: 'R-52',
        nombre: 'Llave Virgen R-52',
        descripcion: 'Compatible Phillips 715',
        marca: 'Alba',
        ubicacion: 'Tablero 1 - Gancho 14',
        precioCompra: 3.50,
        precioVenta: 15.00,
        stockActual: 150.0,
        cantidadMayoreo: 10.0,
        precioMayoreo: 10.00,
      );
    });

    test('Agrega producto con precio público si cantidad es menor al mayoreo', () {
      cart.addProduct(llaveAlba, quantity: 2.0);

      expect(cart.items.length, 1);
      final item = cart.items.first;
      expect(item.cantidad, 2.0);
      expect(item.precioHistorico, 15.00);
      expect(item.totalLinea, 30.00);
      expect(item.ubicacion, 'Tablero 1 - Gancho 14');
      expect(item.costoHistorico, 3.50);
      expect(cart.total, 30.00);
    });

    test('Aplica automáticamente precio de mayoreo al cruzar umbral de volumen', () {
      // Agregamos 10 piezas de llave Alba (umbral mayoreo = 10 piezas a $10.00)
      cart.addProduct(llaveAlba, quantity: 10.0);

      expect(cart.items.length, 1);
      final item = cart.items.first;
      expect(item.cantidad, 10.0);
      expect(item.precioHistorico, 10.00); // Precio mayoreo activado
      expect(item.totalLinea, 100.00);
      expect(cart.total, 100.00);
    });

    test('Control rápido de cantidades incrementa y decrementa correctamente', () {
      cart.addProduct(llaveAlba, quantity: 1.0);
      final itemId = cart.items.first.id;

      cart.incrementQuantity(itemId);
      expect(cart.items.first.cantidad, 2.0);
      expect(cart.total, 30.00);

      cart.decrementQuantity(itemId);
      expect(cart.items.first.cantidad, 1.0);
      expect(cart.total, 15.00);

      // Decrementar a 0 remueve el ítem
      cart.decrementQuantity(itemId);
      expect(cart.items.isEmpty, true);
      expect(cart.total, 0.0);
    });

    test('Atajos + y - modifican el último ítem', () {
      cart.addProduct(llaveAlba, quantity: 1.0);
      expect(cart.items.first.cantidad, 1.0);

      cart.incrementLastItem();
      expect(cart.items.first.cantidad, 2.0);

      cart.decrementLastItem();
      expect(cart.items.first.cantidad, 1.0);
    });

    test('Artículo común se agrega con ubicación en Caja y no afecta catálogo', () {
      cart.addCommonArticle(50.0, description: 'Copia especial sin molde');

      expect(cart.items.length, 1);
      final item = cart.items.first;
      expect(item.productoId, 'ART-COMUN');
      expect(item.nombre, 'Copia especial sin molde');
      expect(item.precioHistorico, 50.0);
      expect(item.totalLinea, 50.0);
      expect(item.ubicacion, 'Caja');
    });

    test('Soporta asignación y cambio dinámico de Niveles de Precio (Multi-Tier Pricing)', () {
      final chipT5 = Product(
        id: 'prod-chip-t5',
        sku: 'CHIP-T5',
        nombre: 'Transponder T5 Carbono',
        descripcion: 'Chip clonable multimarca',
        precioCompra: 18.00,
        precioVenta: 75.00,       // Público
        precioCerrajero: 45.00,   // Cerrajero
        precioTaller: 55.00,      // Taller
        precioMayoreo: 40.00,     // Mayoreo
        cantidadMayoreo: 10.0,
        stockActual: 80.0,
        stockMinimo: 15.0,
      );

      // 1. Agregar con tarifa Cerrajero
      cart.addProduct(chipT5, quantity: 2.0, preferredTier: 'Cerrajero');
      expect(cart.items.length, 1);
      expect(cart.items.first.precioHistorico, 45.00);
      expect(cart.items.first.etiquetaPrecio, 'Cerrajero');
      expect(cart.total, 90.00);

      // 2. Cambiar dinámicamente el nivel de precio en el carrito a Taller
      cart.changeItemPriceTier(cart.items.first.id, chipT5.precioTaller!, 'Taller');
      expect(cart.items.first.precioHistorico, 55.00);
      expect(cart.items.first.etiquetaPrecio, 'Taller');
      expect(cart.total, 110.00);

      // 3. Cambiar a Público
      cart.changeItemPriceTier(cart.items.first.id, chipT5.precioVenta, 'Público');
      expect(cart.items.first.precioHistorico, 75.00);
      expect(cart.items.first.etiquetaPrecio, 'Público');
      expect(cart.total, 150.00);
    });

    test('Pausar venta con alias personalizado (F6) y reanudarla (F7)', () {
      cart.addProduct(llaveAlba, quantity: 3.0);
      expect(cart.items.length, 1);
      expect(cart.total, 45.00);

      // Pausar con alias
      cart.holdCurrentSale(alias: 'Sr. Ramón - Jetta Clásico');
      expect(cart.items.isEmpty, true);
      expect(cart.total, 0.0);
      expect(cart.heldSales.length, 1);
      expect(cart.heldSales.first.alias, 'Sr. Ramón - Jetta Clásico');
      expect(cart.heldSales.first.items.length, 1);

      // Reanudar ticket pausado
      cart.resumeSale(0);
      expect(cart.heldSales.isEmpty, true);
      expect(cart.items.length, 1);
      expect(cart.items.first.nombre, 'Llave Virgen R-52');
      expect(cart.items.first.cantidad, 3.0);
      expect(cart.total, 45.00);
    });
  });
}
