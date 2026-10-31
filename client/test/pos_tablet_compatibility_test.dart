import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/local/models.dart';
import 'package:client/presentation/controllers/cart_controller.dart';
import 'package:client/presentation/widgets/checkout_dialog.dart';
import 'package:client/presentation/widgets/quote_dialog.dart';
import 'package:client/presentation/widgets/insufficient_stock_dialog.dart';
import 'package:client/presentation/widgets/common_article_dialog.dart';
import 'package:client/presentation/widgets/edit_service_line_dialog.dart';

void main() {
  group('ISO/IEC 25010 - Tablet Responsive & Virtual Keyboard QA Suite', () {
    late CartController cart;
    late Product sampleProduct;

    setUp(() {
      cart = CartController();
      sampleProduct = Product(
        id: 'prod-test-r52',
        sku: 'R-52',
        nombre: 'Llave Virgen Alba R52',
        descripcion: 'Compatible cerraduras Phillips',
        precioCompra: 4.0,
        precioVenta: 15.0,
        precioCerrajero: 10.0,
        precioTaller: 12.0,
        precioMayoreo: 8.0,
        stockActual: 25.0,
      );
      cart.addProduct(sampleProduct, quantity: 2);
    });

    // Helper para probar un widget bajo una resolución y teclado virtual específico
    Future<void> testWidgetInTabletResolution({
      required WidgetTester tester,
      required Size resolution,
      required double keyboardInset,
      required Widget child,
    }) async {
      tester.view.physicalSize = resolution;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(body: Center(child: child)),
        ),
      );
      await tester.pumpAndSettle();

      // Validación estricta ISO/IEC 25010: Cero desbordamientos RenderFlex
      expect(tester.takeException(), isNull, reason: 'RenderFlex overflow detectado');
    }

    testWidgets('10" Landscape (1024x768) - CheckoutDialog sin desbordamiento', (tester) async {
      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(1024, 768),
        keyboardInset: 0,
        child: CheckoutDialog(
          cartController: cart,
          corteCajaId: 'corte-test-01',
        ),
      );
      expect(find.text('LIQUIDACIÓN DE TICKET'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('10" Landscape con Teclado Virtual (1024x768, inset=320) - CheckoutDialog desplazable', (tester) async {
      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(1024, 768),
        keyboardInset: 320,
        child: CheckoutDialog(
          cartController: cart,
          corteCajaId: 'corte-test-01',
        ),
      );
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('10" WXGA Landscape (1280x800) - QuoteDialog sin desbordamiento', (tester) async {
      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(1280, 800),
        keyboardInset: 0,
        child: QuoteDialog(
          items: cart.items,
          subtotal: cart.subtotal,
          descuentoTotal: cart.descuentoTotal,
          total: cart.total,
        ),
      );
      expect(find.text('Ticket Digital de Cotización'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8" Portrait (768x1024) - InsufficientStockDialog (Soft-stop)', (tester) async {
      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(768, 1024),
        keyboardInset: 0,
        child: const InsufficientStockDialog(
          productName: 'Pila Botón CR-2032 Energizer',
          currentStock: 2.0,
          requestedQuantity: 5.0,
          location: 'Gaveta B-01',
        ),
      );
      expect(find.text('Inventario Insuficiente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8" Portrait con Teclado (768x1024, inset=320) - CommonArticleDialog', (tester) async {
      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(768, 1024),
        keyboardInset: 320,
        child: CommonArticleDialog(cartController: cart),
      );
      expect(find.text('Artículo Común'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tablet Compacta (800x600) - EditServiceLineDialog con insumo dinámico', (tester) async {
      cart.addDynamicServiceItem(
        service: Product(
          id: 'serv-01',
          nombre: 'Duplicado Tradicional',
          descripcion: 'Corte de llave',
          precioCompra: 0,
          precioVenta: 20.0,
          stockActual: 999.0,
          esServicio: true,
        ),
        insumo: sampleProduct,
        precioCobrado: 20.0,
        etiquetaPrecio: 'Público',
        cantidadInsumoConsumida: 1.0,
      );

      final serviceItem = cart.items.firstWhere((i) => i.esServicio);

      await testWidgetInTabletResolution(
        tester: tester,
        resolution: const Size(800, 600),
        keyboardInset: 0,
        child: EditServiceLineDialog(
          item: serviceItem,
          cartController: cart,
        ),
      );
      expect(find.text('Duplicado Tradicional (Llave Virgen Alba R52)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
