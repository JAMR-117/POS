import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// Dependencias de SQLite
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// Repositorios y Servicios Locales
import 'data/local/database_helper.dart';
import 'data/repositories/sales_repository.dart';
import 'data/repositories/shift_repository.dart';
import 'data/sync/sync_api_client.dart';
import 'data/sync/sync_worker.dart';
import 'data/inventory/inventory_api_client.dart';
import 'data/hardware/printer_service.dart';
import 'data/hardware/esc_pos_ticket_builder.dart';

// Controladores Reactivos
import 'presentation/controllers/cart_controller.dart';
import 'presentation/controllers/alerts_controller.dart';
import 'presentation/controllers/shift_controller.dart';

// Pantalla Principal de Cobro
import 'presentation/screens/pos_screen.dart';
import 'data/repositories/user_repository.dart';
import 'presentation/controllers/auth_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar la factoría adecuada si se ejecuta en navegador Web
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  // 2. Inicialización de la base de datos local
  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database;

  // 3. Instanciación de repositorios
  final salesRepo = SalesRepository(dbHelper: dbHelper);
  final shiftRepo = ShiftRepository(dbHelper: dbHelper);

  // 4. Servicios de Red y Sincronización (Outbox)
  final syncApiClient = SyncApiClient(baseUrl: 'http://127.0.0.1:8080');
  final syncWorker = SyncWorker(dbHelper: dbHelper, apiClient: syncApiClient);
  syncWorker.start();

  // 5. Módulo de Analítica e Inventario Predictivo (BI)
  final inventoryApiClient = InventoryApiClient(baseUrl: 'http://127.0.0.1:8080');

  // 6. Servicio de Impresión Térmica (deshabilitado para web)
  final printerService = PrinterService(
    config: const PrinterConfig(
      type: PrinterConnectionType.disabled,
      address: '127.0.0.1',
      port: 9100,
      paperSize: PaperSize.mm80,
    ),
  );

  // 7. Controladores de Estado
  final cartController = CartController(salesRepository: salesRepo);
  final alertsController = AlertsController(apiClient: inventoryApiClient);
  final shiftController = ShiftController(shiftRepository: shiftRepo);
  final userRepo = UserRepository(dbHelper: dbHelper);
  final authController = AuthController(userRepository: userRepo);

  runApp(PosApp(
    cartController: cartController,
    syncWorker: syncWorker,
    alertsController: alertsController,
    shiftController: shiftController,
    inventoryApiClient: inventoryApiClient,
    printerService: printerService,
    authController: authController,
  ));
}

class PosApp extends StatelessWidget {
  final CartController cartController;
  final SyncWorker syncWorker;
  final AlertsController alertsController;
  final ShiftController shiftController;
  final InventoryApiClient inventoryApiClient;
  final PrinterService printerService;
  final AuthController authController;

  const PosApp({
    super.key,
    required this.cartController,
    required this.syncWorker,
    required this.alertsController,
    required this.shiftController,
    required this.inventoryApiClient,
    required this.printerService,
    required this.authController,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'POS Offline-First',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1F4E79),
        scaffoldBackgroundColor: const Color(0xFFECEFF1),
      ),
      home: PosScreen(
        cartController: cartController,
        syncWorker: syncWorker,
        alertsController: alertsController,
        shiftController: shiftController,
        inventoryApiClient: inventoryApiClient,
        printerService: printerService,
        authController: authController,
        usuarioId: 'cajero-principal',
        nombreNegocio: 'MI TIENDA POS',
      ),
    );
  }
}