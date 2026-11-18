import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/hardware/esc_pos_ticket_builder.dart';
import '../../data/hardware/printer_service.dart';
import '../../data/local/business_config.dart';
import '../../data/local/database_helper.dart';
import '../../data/local/models.dart';
import '../controllers/cart_controller.dart';

class SettingsScreen extends StatefulWidget {
  final PrinterService? printerService;
  final CartController? cartController;
  final bool showAppBar;
  final VoidCallback? onSettingsSaved;

  const SettingsScreen({
    super.key,
    this.printerService,
    this.cartController,
    this.showAppBar = true,
    this.onSettingsSaved,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  bool _isLoading = true;

  // 1. Datos del Negocio
  String? _logoBase64;
  final TextEditingController _businessNameCtrl = TextEditingController();
  final TextEditingController _businessSubtitleCtrl = TextEditingController();
  final TextEditingController _pdfDirectoryCtrl = TextEditingController(text: r'C:\POS\Cotizaciones');
  final TextEditingController _businessRfcCtrl = TextEditingController();
  final TextEditingController _businessPhoneCtrl = TextEditingController();
  final TextEditingController _businessAddressCtrl = TextEditingController();
  final TextEditingController _businessSloganCtrl = TextEditingController();
  final TextEditingController _businessEmailCtrl = TextEditingController();
  bool _mayoreoAutoEnabled = true;
  final TextEditingController _mayoreoUmbralCtrl = TextEditingController(text: '5.0');

  // 2. Configuración del Ticket Térmico y Plantilla
  final TextEditingController _ticketHeaderCtrl = TextEditingController();
  final TextEditingController _ticketFooterCtrl = TextEditingController();
  final TextEditingController _ticketGarantiaCtrl = TextEditingController();
  String _paperWidth = '80mm'; // '58mm' o '80mm'
  bool _ticketPrintTax = false;
  bool _ticketAutoDrawer = true;

  // Switches de visibilidad de plantilla de ticket
  bool _ticketMostrarLogo = true;
  bool _ticketMostrarNombre = true;
  bool _ticketMostrarContacto = true;
  bool _ticketMostrarFolioFecha = true;
  bool _ticketMostrarCajero = true;
  bool _ticketMostrarCliente = true;
  bool _ticketMostrarDescuentosRedondeo = true;
  bool _ticketMostrarTotalLetra = true;
  bool _ticketMostrarCodigoBarras = true;

  // Hardware de Impresión Física (Puente Go / Red / Spooler)
  PrinterConnectionType _printerType = PrinterConnectionType.windowsSpooler;
  String _selectedPrinterName = '';
  final TextEditingController _printerAddressCtrl = TextEditingController(text: '192.168.1.200');
  final TextEditingController _printerPortCtrl = TextEditingController(text: '9100');
  List<String> _detectedPrinters = [];
  List<String> _detectedSerialPorts = [];
  bool _creditoClientesHabilitado = true;
  String _ticketFontFamily = 'Fuente A';
  String _ticketFontSize = 'Normal';

  // Panel interactivo de prueba de lector de codigo de barras
  final TextEditingController _barcodeTestCtrl = TextEditingController();
  final FocusNode _barcodeTestFocus = FocusNode();
  String _lastBarcodeRead = '';
  int _barcodeCharCount = 0;
  int _barcodeDurationMs = 0;
  DateTime? _barcodeStartTime;
  bool _isDetectingPrinters = false;
  bool _isTestingPrinter = false;

  // 3. Matriz de Permisos para Cajeros
  bool _permisoDescuentos = false;
  bool _permisoCancelarTickets = false;
  bool _permisoDarCredito = false;
  bool _permisoVerCostosCompra = false;
  bool _permisoMovimientosCaja = true;
  bool _permisoEjecutarCorteZ = false;
  bool _permisoEditarPrecios = false;
  bool _permisoModificarStock = false;

  // 4. Facturación CFDI
  final TextEditingController _cfdiRegimenCtrl = TextEditingController();
  final TextEditingController _cfdiLugarExpedicionCtrl = TextEditingController();
  final TextEditingController _cfdiSerieCtrl = TextEditingController();
  final TextEditingController _cfdiFolioCtrl = TextEditingController();

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _businessNameCtrl.addListener(_onFieldChanged);
    _businessSubtitleCtrl.addListener(_onFieldChanged);
    _businessAddressCtrl.addListener(_onFieldChanged);
    _businessRfcCtrl.addListener(_onFieldChanged);
    _businessPhoneCtrl.addListener(_onFieldChanged);
    _ticketHeaderCtrl.addListener(_onFieldChanged);
    _ticketFooterCtrl.addListener(_onFieldChanged);
    _ticketGarantiaCtrl.addListener(_onFieldChanged);

    _loadSettings();
  }

  @override
  void dispose() {
    _businessNameCtrl.removeListener(_onFieldChanged);
    _businessSubtitleCtrl.removeListener(_onFieldChanged);
    _businessAddressCtrl.removeListener(_onFieldChanged);
    _businessRfcCtrl.removeListener(_onFieldChanged);
    _businessPhoneCtrl.removeListener(_onFieldChanged);
    _ticketHeaderCtrl.removeListener(_onFieldChanged);
    _ticketFooterCtrl.removeListener(_onFieldChanged);
    _ticketGarantiaCtrl.removeListener(_onFieldChanged);

    _tabController.dispose();
    _barcodeTestCtrl.dispose();
    _barcodeTestFocus.dispose();
    _businessNameCtrl.dispose();
    _businessSubtitleCtrl.dispose();
    _pdfDirectoryCtrl.dispose();
    _businessRfcCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessSloganCtrl.dispose();
    _businessEmailCtrl.dispose();
    _mayoreoUmbralCtrl.dispose();
    _ticketHeaderCtrl.dispose();
    _ticketFooterCtrl.dispose();
    _ticketGarantiaCtrl.dispose();
    _printerAddressCtrl.dispose();
    _printerPortCtrl.dispose();
    _cfdiRegimenCtrl.dispose();
    _cfdiLugarExpedicionCtrl.dispose();
    _cfdiSerieCtrl.dispose();
    _cfdiFolioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final cfg = await BusinessConfig.load(dbHelper: _dbHelper);

    _logoBase64 = cfg.logoBase64;
    _businessNameCtrl.text = cfg.negocioNombre;
    _businessSubtitleCtrl.text = cfg.negocioLeyenda;
    _businessSloganCtrl.text = cfg.negocioSlogan;
    _businessRfcCtrl.text = cfg.negocioRfc;
    _businessPhoneCtrl.text = cfg.negocioTelefono;
    _businessAddressCtrl.text = cfg.negocioDireccion;
    _businessEmailCtrl.text = cfg.negocioEmail;
    _pdfDirectoryCtrl.text = cfg.rutaGuardadoPdf;
    _mayoreoAutoEnabled = cfg.mayoreoAutoEnabled;
    _mayoreoUmbralCtrl.text = cfg.mayoreoUmbralGlobal.toString();

    _ticketHeaderCtrl.text = cfg.ticketHeader;
    _ticketFooterCtrl.text = cfg.ticketFooter;
    _ticketGarantiaCtrl.text = cfg.ticketGarantia;
    _paperWidth = cfg.ticketAnchoPapel;
    _ticketMostrarLogo = cfg.ticketMostrarLogo;
    _ticketMostrarNombre = cfg.ticketMostrarNombre;
    _ticketMostrarContacto = cfg.ticketMostrarContacto;
    _ticketMostrarFolioFecha = cfg.ticketMostrarFolioFecha;
    _ticketMostrarCajero = cfg.ticketMostrarCajero;
    _ticketMostrarCliente = cfg.ticketMostrarCliente;
    _ticketMostrarDescuentosRedondeo = cfg.ticketMostrarDescuentosRedondeo;
    _ticketMostrarTotalLetra = cfg.ticketMostrarTotalLetra;
    _ticketMostrarCodigoBarras = cfg.ticketMostrarCodigoBarras;
    _ticketPrintTax = cfg.ticketImprimirImpuestos;
    _ticketAutoDrawer = cfg.ticketAbrirCajon;
    _creditoClientesHabilitado = cfg.creditoClientesHabilitado;
    _ticketFontFamily = cfg.ticketFontFamily;
    _ticketFontSize = cfg.ticketFontSize;

    _permisoDescuentos = cfg.permisoDescuentos;
    _permisoCancelarTickets = cfg.permisoCancelarTickets;
    _permisoDarCredito = cfg.permisoDarCredito;
    _permisoVerCostosCompra = cfg.permisoVerCostosCompra;
    _permisoMovimientosCaja = cfg.permisoMovimientosCaja;
    _permisoEjecutarCorteZ = cfg.permisoEjecutarCorteZ;
    _permisoEditarPrecios = cfg.permisoEditarPrecios;
    _permisoModificarStock = cfg.permisoModificarStock;

    _cfdiRegimenCtrl.text = cfg.cfdiRegimenFiscal;
    _cfdiLugarExpedicionCtrl.text = cfg.cfdiLugarExpedicion;
    _cfdiSerieCtrl.text = cfg.cfdiSerie;
    _cfdiFolioCtrl.text = cfg.cfdiFolio;

    if (widget.printerService != null) {
      final pCfg = widget.printerService!.config;
      _printerType = pCfg.type;
      _selectedPrinterName = pCfg.printerName;
      _printerAddressCtrl.text = pCfg.address;
      _printerPortCtrl.text = pCfg.port.toString();
      _paperWidth = pCfg.paperSize == PaperSize.mm58 ? '58mm' : '80mm';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Unificado: Guarda todos los parámetros de todas las pestañas de una sola vez
  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    final parsedUmbral = double.tryParse(_mayoreoUmbralCtrl.text.trim()) ?? 5.0;

    final newConfig = BusinessConfig(
      negocioNombre: _businessNameCtrl.text.trim().isEmpty ? 'CARprog' : _businessNameCtrl.text.trim(),
      negocioLeyenda: _businessSubtitleCtrl.text.trim(),
      negocioSlogan: _businessSloganCtrl.text.trim(),
      negocioRfc: _businessRfcCtrl.text.trim(),
      negocioTelefono: _businessPhoneCtrl.text.trim(),
      negocioDireccion: _businessAddressCtrl.text.trim(),
      negocioEmail: _businessEmailCtrl.text.trim(),
      logoBase64: _logoBase64,
      rutaGuardadoPdf: _pdfDirectoryCtrl.text.trim(),
      mayoreoAutoEnabled: _mayoreoAutoEnabled,
      mayoreoUmbralGlobal: parsedUmbral,
      ticketHeader: _ticketHeaderCtrl.text.trim(),
      ticketFooter: _ticketFooterCtrl.text.trim(),
      ticketGarantia: _ticketGarantiaCtrl.text.trim(),
      ticketAnchoPapel: _paperWidth,
      ticketMostrarLogo: _ticketMostrarLogo,
      ticketMostrarNombre: _ticketMostrarNombre,
      ticketMostrarContacto: _ticketMostrarContacto,
      ticketMostrarFolioFecha: _ticketMostrarFolioFecha,
      ticketMostrarCajero: _ticketMostrarCajero,
      ticketMostrarCliente: _ticketMostrarCliente,
      ticketMostrarDescuentosRedondeo: _ticketMostrarDescuentosRedondeo,
      ticketMostrarTotalLetra: _ticketMostrarTotalLetra,
      ticketMostrarCodigoBarras: _ticketMostrarCodigoBarras,
      ticketImprimirImpuestos: _ticketPrintTax,
      ticketAbrirCajon: _ticketAutoDrawer,
      creditoClientesHabilitado: _creditoClientesHabilitado,
      ticketFontFamily: _ticketFontFamily,
      ticketFontSize: _ticketFontSize,
      permisoDescuentos: _permisoDescuentos,
      permisoCancelarTickets: _permisoCancelarTickets,
      permisoDarCredito: _permisoDarCredito,
      permisoVerCostosCompra: _permisoVerCostosCompra,
      permisoMovimientosCaja: _permisoMovimientosCaja,
      permisoEjecutarCorteZ: _permisoEjecutarCorteZ,
      permisoEditarPrecios: _permisoEditarPrecios,
      permisoModificarStock: _permisoModificarStock,
      cfdiRegimenFiscal: _cfdiRegimenCtrl.text.trim(),
      cfdiLugarExpedicion: _cfdiLugarExpedicionCtrl.text.trim(),
      cfdiSerie: _cfdiSerieCtrl.text.trim(),
      cfdiFolio: _cfdiFolioCtrl.text.trim(),
    );

    await newConfig.save(dbHelper: _dbHelper);

    widget.cartController?.setMayoreoConfig(autoEnabled: _mayoreoAutoEnabled, umbral: parsedUmbral);

    if (widget.printerService != null) {
      final newCfg = PrinterConfig(
        type: _printerType,
        printerName: _selectedPrinterName,
        address: _printerAddressCtrl.text.trim(),
        port: int.tryParse(_printerPortCtrl.text.trim()) ?? 9100,
        paperSize: _paperWidth == '58mm' ? PaperSize.mm58 : PaperSize.mm80,
      );
      await widget.printerService!.saveConfig(newCfg);
    }

    widget.onSettingsSaved?.call();

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configuración del sistema guardada exitosamente.'),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildUnifiedSaveButton({bool compact = false}) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 2,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 8 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: _isLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.save, size: 18),
      label: Text(
        '💾 Guardar Configuración',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: compact ? 12 : 14),
      ),
      onPressed: _isLoading ? null : _saveSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Configuración del Sistema', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF1F4E79),
              foregroundColor: Colors.white,
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: const Color(0xFFFFB74D),
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.store), text: 'Datos del Negocio'),
                  Tab(icon: Icon(Icons.receipt), text: 'Ticket Térmico'),
                  Tab(icon: Icon(Icons.security), text: 'Permisos de Cajeros'),
                  Tab(icon: Icon(Icons.description), text: 'Facturación / CFDI'),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Center(child: _buildUnifiedSaveButton(compact: true)),
                ),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!widget.showAppBar)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            labelColor: const Color(0xFF1F4E79),
                            unselectedLabelColor: Colors.black54,
                            indicatorColor: const Color(0xFF1F4E79),
                            indicatorWeight: 3,
                            tabs: const [
                              Tab(icon: Icon(Icons.store, size: 18), text: 'Datos del Negocio'),
                              Tab(icon: Icon(Icons.receipt, size: 18), text: 'Ticket Térmico'),
                              Tab(icon: Icon(Icons.security, size: 18), text: 'Permisos de Cajeros'),
                              Tab(icon: Icon(Icons.description, size: 18), text: 'Facturación / CFDI'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildUnifiedSaveButton(compact: true),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBusinessDataTab(),
                      _buildTicketConfigTab(),
                      _buildCashierPermissionsTab(),
                      _buildCfdiTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // --- MÉTODOS DE SOPORTE PARA ARCHIVOS ---

  Future<void> _pickLogoImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final bytes = result.files.first.bytes;
        if (bytes != null) {
          setState(() {
            _logoBase64 = base64Encode(bytes);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Imagen de logo seleccionada. Presione "Guardar Configuración" para aplicar.'),
                backgroundColor: Color(0xFF2E7D32),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error seleccionando imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetDefaultLogo() {
    setState(() {
      _logoBase64 = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Se ha restablecido el logo al valor por defecto.')),
    );
  }

  Future<void> _pickPdfDirectory() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null && dir.isNotEmpty) {
        setState(() {
          _pdfDirectoryCtrl.text = dir;
        });
      }
    } catch (_) {}
  }

  // --- TAB 1: DATOS DEL NEGOCIO ---
  Widget _buildBusinessDataTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        // Identidad Visual y Logo
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _logoBase64 != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            base64Decode(_logoBase64!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.business, size: 44, color: Color(0xFF1F4E79)),
                        ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Logo del Negocio',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Aparece en el encabezado del sistema, tickets térmicos, cotizaciones y comprobantes.',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F4E79),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('Subir Imagen PNG/JPG'),
                            onPressed: _pickLogoImage,
                          ),
                          if (_logoBase64 != null) ...[
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Quitar Logo'),
                              onPressed: _resetDefaultLogo,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Datos del Negocio
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Datos Generales de la Empresa',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _businessNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre Comercial del Negocio *',
                          hintText: 'Ej. CARprog',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _businessSubtitleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Giro o Leyenda Comercial',
                          hintText: 'Ej. Cerrajería y Electrónica Automotriz',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _businessSloganCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slogan o Mensaje Comercial',
                    hintText: 'Ej. Especialistas en Llaves con Chip, Controles y Aperturas',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _businessRfcCtrl,
                        decoration: const InputDecoration(labelText: 'RFC del Negocio', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _businessPhoneCtrl,
                        decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _businessEmailCtrl,
                        decoration: const InputDecoration(labelText: 'Correo Electrónico', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _businessAddressCtrl,
                  decoration: const InputDecoration(labelText: 'Dirección Comercial Física', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),

        // Ruta de Guardado de PDFs
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Carpeta de Exportación de Cotizaciones y Facturas PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Los archivos PDF generados desde el módulo de Cotizaciones se guardarán automáticamente en esta ruta local de su PC.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pdfDirectoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ruta en Disco Duro',
                          hintText: r'C:\POS\Cotizaciones',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1F4E79),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Examinar...'),
                      onPressed: _pickPdfDirectory,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Crédito y Cuentas por Cobrar a Clientes
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.credit_score, color: Color(0xFF1F4E79), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Crédito a Clientes y Cuentas por Cobrar',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('💳 Habilitar Ventas y Crédito a Clientes', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Permite otorgar créditos en caja y llevar cuentas corrientes por cobrar. Si se desactiva, se oculta la opción de pago a Crédito en caja.'),
                  value: _creditoClientesHabilitado,
                  activeThumbColor: const Color(0xFF1F4E79),
                  onChanged: (val) => setState(() => _creditoClientesHabilitado = val),
                ),
              ],
            ),
          ),
        ),

        // Mayoreo General Automático
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activación Global de Precios Mayoreo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aplicar precio de mayoreo automáticamente por volumen'),
                  subtitle: const Text('Cuando la suma de artículos de una partida alcance o supere el umbral.'),
                  value: _mayoreoAutoEnabled,
                  activeThumbColor: const Color(0xFF1F4E79),
                  onChanged: (val) => setState(() => _mayoreoAutoEnabled = val),
                ),
                if (_mayoreoAutoEnabled) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _mayoreoUmbralCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Umbral Global por Defecto (Piezas)',
                        hintText: '5.0',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- TAB 2: TICKET TÉRMICO (SPLIT-VIEW CON VISTA PREVIA EN VIVO) ---
  Widget _buildTicketConfigTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Panel Izquierdo: Controles
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.all(20.0),
                  children: [
                    _buildHardwareSection(),
                    const SizedBox(height: 20),
                    _buildTicketControlsSection(),
                  ],
                ),
              ),
              // Separador Vertical
              Container(width: 1, color: Colors.grey.shade300),
              // Panel Derecho: Vista Previa Térmica en Vivo
              Expanded(
                flex: 2,
                child: Container(
                  color: const Color(0xFFECEFF1),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: _buildThermalTicketLivePreview(),
                    ),
                  ),
                ),
              ),
            ],
          );
        } else {
          // Pantalla estrecha: apilado
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildHardwareSection(),
              const SizedBox(height: 20),
              _buildTicketControlsSection(),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '👁️ VISTA PREVIA EN VIVO DEL TICKET TÉRMICO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79)),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: _buildThermalTicketLivePreview()),
              const SizedBox(height: 30),
            ],
          );
        }
      },
    );
  }

  Widget _buildHardwareSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.print, color: Color(0xFF1F4E79), size: 22),
                SizedBox(width: 8),
                Text(
                  'HARDWARE DE IMPRESIÓN FÍSICA (TÉRMICA ESC/POS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Tipo de Conexión:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<PrinterConnectionType>(
              initialValue: _printerType,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(
                  value: PrinterConnectionType.windowsSpooler,
                  child: Text('🖨️ Impresora Térmica USB de Windows (Vía Backend Local)'),
                ),
                DropdownMenuItem(
                  value: PrinterConnectionType.network,
                  child: Text('🌐 Impresora de Red Ethernet / Wi-Fi (Socket Raw TCP 9100)'),
                ),
                DropdownMenuItem(
                  value: PrinterConnectionType.systemDialog,
                  child: Text('📄 Vista Previa Térmica en Pantalla / Diálogo'),
                ),
                DropdownMenuItem(
                  value: PrinterConnectionType.disabled,
                  child: Text('🚫 Sin Impresora (Deshabilitada)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _printerType = val);
              },
            ),
            const SizedBox(height: 12),

            if (_printerType == PrinterConnectionType.windowsSpooler) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Impresora de Windows Seleccionada:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 6),
                        if (_detectedPrinters.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue: _detectedPrinters.contains(_selectedPrinterName) ? _selectedPrinterName : _detectedPrinters.first,
                            isExpanded: true,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: _detectedPrinters
                                .map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedPrinterName = val);
                            },
                          )
                        else
                          TextField(
                            controller: TextEditingController(text: _selectedPrinterName),
                            decoration: const InputDecoration(
                              labelText: 'Nombre de la Impresora',
                              hintText: 'Ej. POS-80, EPSON TM-T20',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (val) => _selectedPrinterName = val.trim(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    icon: _isDetectingPrinters
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search, size: 16),
                    label: const Text('Detectar'),
                    onPressed: _isDetectingPrinters ? null : _detectWindowsPrinters,
                  ),
                ],
              ),
            ] else if (_printerType == PrinterConnectionType.network) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _printerAddressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Dirección IP de la Impresora',
                        hintText: '192.168.1.200',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _printerPortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Puerto TCP',
                        hintText: '9100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: _isTestingPrinter
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.receipt, size: 16),
                  label: const Text('Imprimir Ticket de Prueba', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _isTestingPrinter ? null : _testPrint,
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1F4E79),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: _isDetectingPrinters
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Escanear Dispositivos e Impresoras', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _isDetectingPrinters ? null : _detectWindowsPrinters,
                ),
              ],
            ),
            if (_detectedPrinters.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Impresoras detectadas en el sistema:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _detectedPrinters.map((p) {
                  final isCurrent = _selectedPrinterName == p;
                  return ActionChip(
                    avatar: Icon(Icons.print, size: 14, color: isCurrent ? Colors.white : const Color(0xFF1F4E79)),
                    label: Text(p, style: TextStyle(fontSize: 11, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                    backgroundColor: isCurrent ? const Color(0xFF1F4E79) : Colors.grey.shade100,
                    labelStyle: TextStyle(color: isCurrent ? Colors.white : Colors.black87),
                    onPressed: () {
                      setState(() => _selectedPrinterName = p);
                    },
                  );
                }).toList(),
              ),
            ],
            if (_detectedSerialPorts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Puertos serie detectados: ${_detectedSerialPorts.join(", ")}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // PANEL DE PRUEBA DE LECTOR DE CÓDIGO DE BARRAS (PHASE 6)
            const Row(
              children: [
                Icon(Icons.qr_code_scanner, color: Color(0xFF1F4E79), size: 20),
                SizedBox(width: 8),
                Text('🔫 Probar Lector de Código de Barras (Wedge HID)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F4E79))),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Haz clic en la caja de abajo y realiza un disparo con tu lector físico USB/Bluetooth. Se calculará el tiempo de ráfaga y formato:',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeTestCtrl,
                    focusNode: _barcodeTestFocus,
                    decoration: InputDecoration(
                      labelText: 'Dispara con el lector físico aquí...',
                      hintText: 'Esperando ráfaga de código de barras...',
                      prefixIcon: const Icon(Icons.barcode_reader),
                      suffixIcon: _barcodeTestCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setState(() {
                                  _barcodeTestCtrl.clear();
                                  _lastBarcodeRead = '';
                                  _barcodeCharCount = 0;
                                  _barcodeDurationMs = 0;
                                });
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      _barcodeStartTime ??= DateTime.now();
                    },
                    onSubmitted: (val) {
                      final now = DateTime.now();
                      final dur = _barcodeStartTime != null ? now.difference(_barcodeStartTime!).inMilliseconds : 15;
                      _barcodeStartTime = null;
                      setState(() {
                        _lastBarcodeRead = val.trim();
                        _barcodeCharCount = _lastBarcodeRead.length;
                        _barcodeDurationMs = dur;
                      });
                      _barcodeTestCtrl.clear();
                      _barcodeTestFocus.requestFocus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F4E79),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('Enfocar Lector'),
                  onPressed: () => _barcodeTestFocus.requestFocus(),
                ),
              ],
            ),
            if (_lastBarcodeRead.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Código Leído: $_lastBarcodeRead', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20))),
                          Text('Longitud: $_barcodeCharCount caracteres | Ráfaga: $_barcodeDurationMs ms | Formato: ${_lastBarcodeRead.length == 13 ? "EAN-13" : (_lastBarcodeRead.length == 12 ? "UPC-A" : "Code 128 / SKU")}', style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTicketControlsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PLANTILLA Y FORMATO DEL TICKET',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F4E79)),
            ),
            const SizedBox(height: 14),

            // SECCIÓN 1: ENCABEZADO COMERCIAL
            _buildSectionHeader('1. Encabezado Comercial'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Logo del Negocio'),
              subtitle: const Text('Imprime el logo en el encabezado si la impresora soporta gráficos.'),
              value: _ticketMostrarLogo,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarLogo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Nombre y Giro/Leyenda Comercial'),
              subtitle: const Text('Ej. CARprog | Cerrajería y Electrónica'),
              value: _ticketMostrarNombre,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarNombre = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Datos Fiscales y de Contacto'),
              subtitle: const Text('RFC, Dirección y Teléfono de atención.'),
              value: _ticketMostrarContacto,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarContacto = val),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _ticketHeaderCtrl,
              decoration: const InputDecoration(
                labelText: 'Mensaje Superior / Bienvenida',
                hintText: '¡GRACIAS POR SU PREFERENCIA!',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SizedBox(height: 18),

            // SECCIÓN 2: DATOS OPERATIVOS
            _buildSectionHeader('2. Datos Operativos'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Folio y Fecha/Hora'),
              value: _ticketMostrarFolioFecha,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarFolioFecha = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Cajero y Turno de Caja'),
              value: _ticketMostrarCajero,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarCajero = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Nombre del Cliente'),
              value: _ticketMostrarCliente,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarCliente = val),
            ),

            const SizedBox(height: 18),

            // SECCIÓN 3: CUERPO Y TOTALES
            _buildSectionHeader('3. Cuerpo y Totales'),
            Row(
              children: [
                const Text('Ancho de Papel Térmico:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('80 mm (Estándar Mostrador)'),
                  selected: _paperWidth == '80mm',
                  onSelected: (val) {
                    if (val) setState(() => _paperWidth = '80mm');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('58 mm (Portátil / Mini)'),
                  selected: _paperWidth == '58mm',
                  onSelected: (val) {
                    if (val) setState(() => _paperWidth = '58mm');
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Tipografía de Ticket:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Fuente A (12x24)'),
                  selected: _ticketFontFamily == 'Fuente A',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontFamily = 'Fuente A');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Fuente B (9x17)'),
                  selected: _ticketFontFamily == 'Fuente B',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontFamily = 'Fuente B');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Monospace'),
                  selected: _ticketFontFamily == 'Monospace',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontFamily = 'Monospace');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Consola'),
                  selected: _ticketFontFamily == 'Consola',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontFamily = 'Consola');
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Tamaño de Fuente:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Pequeña'),
                  selected: _ticketFontSize == 'Pequeña',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontSize = 'Pequeña');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Normal'),
                  selected: _ticketFontSize == 'Normal',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontSize = 'Normal');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Mediana'),
                  selected: _ticketFontSize == 'Mediana',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontSize = 'Mediana');
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Grande'),
                  selected: _ticketFontSize == 'Grande',
                  onSelected: (val) {
                    if (val) setState(() => _ticketFontSize = 'Grande');
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Desglose de Descuentos y Redondeo'),
              subtitle: const Text('Muestra líneas de descuento y ajuste de centavos.'),
              value: _ticketMostrarDescuentosRedondeo,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarDescuentosRedondeo = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Importe con Letra (Pesos M.N.)'),
              subtitle: const Text('Ej. (UN MIL DOSCIENTOS PESOS 00/100 M.N.)'),
              value: _ticketMostrarTotalLetra,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarTotalLetra = val),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Abrir cajón de dinero automáticamente al cobrar'),
              value: _ticketAutoDrawer,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketAutoDrawer = val),
            ),

            const SizedBox(height: 18),

            // SECCIÓN 4: PIE DE TICKET Y GARANTÍA
            _buildSectionHeader('4. Pie de Ticket y Garantía'),
            TextField(
              controller: _ticketGarantiaCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Póliza de Garantía / Condiciones de Devolución',
                hintText: 'Garantía de duplicados y programación: 30 días presentando este comprobante.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar Código de Barras al Pie del Ticket'),
              subtitle: const Text('Imprime el código de barras legible por pistola láser con el folio de la venta.'),
              value: _ticketMostrarCodigoBarras,
              activeThumbColor: const Color(0xFF1F4E79),
              onChanged: (val) => setState(() => _ticketMostrarCodigoBarras = val),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ticketFooterCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mensaje de Agradecimiento / Despedida',
                hintText: 'La nota original se entregará con la mercancía.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F4E79).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F4E79)),
      ),
    );
  }

  // --- VISTA PREVIA ULTRA REALISTA EN VIVO DEL TICKET TÉRMICO ---
  Widget _buildThermalTicketLivePreview() {
    final is58 = _paperWidth == '58mm';
    final previewWidth = is58 ? 260.0 : 340.0;
    final dividerChar = is58 ? '----------------------------' : '----------------------------------------';
    final doubleDivider = is58 ? '============================' : '========================================';

    final businessName = _businessNameCtrl.text.trim().isNotEmpty ? _businessNameCtrl.text.trim() : 'CARprog';
    final businessSubtitle = _businessSubtitleCtrl.text.trim();
    final address = _businessAddressCtrl.text.trim().isNotEmpty ? _businessAddressCtrl.text.trim() : 'Av. Tecnológico #405';
    final rfc = _businessRfcCtrl.text.trim().isNotEmpty ? _businessRfcCtrl.text.trim() : 'XAXX010101000';
    final phone = _businessPhoneCtrl.text.trim().isNotEmpty ? _businessPhoneCtrl.text.trim() : '555-123-4567';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicador del formato
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1F4E79),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                'Vista Previa Térmica ($_paperWidth)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
        ),

        // Cuerpo del Ticket Térmico con aspecto realista
        Container(
          width: previewWidth,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8), // Color marfil/papel térmico sutil
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(horizontal: is58 ? 10 : 16, vertical: 16),
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: _ticketFontFamily == 'Consola' ? 'Consolas' : (_ticketFontFamily == 'Courier' ? 'Courier' : 'monospace'),
              fontSize: _ticketFontSize == 'Pequeña' ? 10.0 : (_ticketFontSize == 'Mediana' ? 12.5 : (_ticketFontSize == 'Grande' ? 14.0 : 11.5)),
              color: const Color(0xFF1A1A1A),
              height: 1.25,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Logo
                if (_ticketMostrarLogo) ...[
                  Center(
                    child: _logoBase64 != null
                        ? SizedBox(
                            height: 40,
                            child: Image.memory(base64Decode(_logoBase64!), fit: BoxFit.contain),
                          )
                        : const Icon(Icons.key, size: 28, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                ],

                // 2. Nombre y Leyenda
                if (_ticketMostrarNombre) ...[
                  Text(
                    businessName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (businessSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      businessSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ],
                ],

                // 3. Contacto y Fiscal
                if (_ticketMostrarContacto) ...[
                  const SizedBox(height: 4),
                  Text(address, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                  Text('RFC: $rfc', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                  Text('TEL: $phone', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                ],

                // Mensaje Superior
                if (_ticketHeaderCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _ticketHeaderCtrl.text.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ],

                const SizedBox(height: 6),
                Text(doubleDivider, textAlign: TextAlign.center, maxLines: 1),
                const SizedBox(height: 4),

                // 4. Folio y Operativos
                if (_ticketMostrarFolioFecha) ...[
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('FOLIO: TK-008492', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('13/11/26 14:30'),
                    ],
                  ),
                ],
                if (_ticketMostrarCliente) ...[
                  const Text('CLIENTE: Público en General'),
                ],
                if (_ticketMostrarCajero) ...[
                  const Text('CAJERO: cajero1 | TURNO: 01A'),
                ],

                const SizedBox(height: 4),
                Text(dividerChar, textAlign: TextAlign.center, maxLines: 1),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('CANT  DESCRIPCIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(dividerChar, textAlign: TextAlign.center, maxLines: 1),

                // Partidas de ejemplo
                _buildSampleItemRow('2x Llave Ford c/chip', '\$450.00'),
                if (_ticketMostrarDescuentosRedondeo)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('  (Desc. Mayoreo)', style: TextStyle(color: Colors.black54)),
                      Text('-\$50.00', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                _buildSampleItemRow('1x Control Alarma 315Mhz', '\$350.00'),
                _buildSampleItemRow('1x Programación Llave', '\$250.00'),

                const SizedBox(height: 4),
                Text(dividerChar, textAlign: TextAlign.center, maxLines: 1),

                // Totales
                _buildTotalRow('SUBTOTAL:', '\$1,050.00'),
                if (_ticketMostrarDescuentosRedondeo) ...[
                  _buildTotalRow('DESCUENTO:', '-\$50.00'),
                  _buildTotalRow('REDONDEO:', '+\$0.00'),
                ],
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TOTAL A PAGAR:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('\$1,000.00', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),

                if (_ticketMostrarTotalLetra) ...[
                  const SizedBox(height: 4),
                  const Text('(UN MIL PESOS 00/100 M.N.)', style: TextStyle(fontSize: 9.5)),
                ],

                const SizedBox(height: 4),
                Text(dividerChar, textAlign: TextAlign.center, maxLines: 1),
                _buildTotalRow('Forma de pago: EFECTIVO', '\$1,000.00'),
                _buildTotalRow('CAMBIO:', '\$0.00'),
                Text(doubleDivider, textAlign: TextAlign.center, maxLines: 1),

                // Garantía y Leyendas
                if (_ticketGarantiaCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _ticketGarantiaCtrl.text.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9.5),
                  ),
                ],

                if (_ticketFooterCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _ticketFooterCtrl.text.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9.5),
                  ),
                ],

                const SizedBox(height: 8),
                // Código de barras simulado
                const Text(
                  '|| | ||||| || |||||| | ||',
                  textAlign: TextAlign.center,
                  style: TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.bold),
                ),
                const Text(
                  '* TK-008492 *',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9),
                ),
                const SizedBox(height: 8),
                const Text(
                  '- - - - - CORTE DE PAPEL - - - - -',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black38, fontSize: 8),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSampleItemRow(String description, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(description, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(amount),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(amount),
        ],
      ),
    );
  }

  // --- HARDWARE PRINTER HELPERS ---
  Future<void> _detectWindowsPrinters() async {
    setState(() => _isDetectingPrinters = true);
    try {
      if (widget.printerService != null) {
        final printers = await widget.printerService!.fetchInstalledPrinters();
        final devInfo = await widget.printerService!.getDetectedDevices();
        setState(() {
          _detectedPrinters = printers;
          if (devInfo['serial_ports'] is List) {
            _detectedSerialPorts = List<String>.from(devInfo['serial_ports']);
          }
          if (_detectedPrinters.isNotEmpty && !_detectedPrinters.contains(_selectedPrinterName)) {
            _selectedPrinterName = _detectedPrinters.first;
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Detección completada: ${_detectedPrinters.length} impresoras y ${_detectedSerialPorts.length} puertos COM detectados.'),
              backgroundColor: const Color(0xFF2E7D32),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error detectando dispositivos: $e'), backgroundColor: Colors.orange.shade800),
        );
      }
    }
    if (mounted) setState(() => _isDetectingPrinters = false);
  }

  Future<void> _testPrint() async {
    setState(() => _isTestingPrinter = true);
    try {
      final sampleData = TicketPrintData(
        negocioNombre: _businessNameCtrl.text.trim().isNotEmpty ? _businessNameCtrl.text.trim() : 'CARprog',
        negocioLeyenda: _businessSubtitleCtrl.text.trim(),
        direccion: _businessAddressCtrl.text.trim(),
        rfc: _businessRfcCtrl.text.trim(),
        telefono: _businessPhoneCtrl.text.trim(),
        mensajeSuperior: _ticketHeaderCtrl.text.trim(),
        folio: 'TEST-0001',
        fecha: DateTime.now(),
        cajero: 'ADMIN',
        turnoId: 'PRUEBA',
        items: [
          SaleDetailItem(
            id: 'item-1',
            productoId: 'p-1',
            nombre: 'Llave Ford c/chip',
            descripcion: 'Llave de prueba con transponder',
            cantidad: 1.0,
            precioHistorico: 450.0,
            costoHistorico: 150.0,
            descuentoLinea: 0.0,
            totalLinea: 450.0,
            etiquetaPrecio: 'Público',
          ),
        ],
        subtotal: 450.0,
        total: 450.0,
        pagos: [PaymentMethodBreakdown(metodo: 'Efectivo', monto: 450.0)],
        cambio: 0.0,
        piePagina: _ticketFooterCtrl.text.trim(),
        garantia: _ticketGarantiaCtrl.text.trim(),
        mostrarLogo: _ticketMostrarLogo,
        mostrarNombre: _ticketMostrarNombre,
        mostrarContacto: _ticketMostrarContacto,
        mostrarFolioFecha: _ticketMostrarFolioFecha,
        mostrarCajero: _ticketMostrarCajero,
        mostrarCliente: _ticketMostrarCliente,
        mostrarDescuentosRedondeo: _ticketMostrarDescuentosRedondeo,
        mostrarTotalLetra: _ticketMostrarTotalLetra,
        mostrarCodigoBarras: _ticketMostrarCodigoBarras,
      );

      if (widget.printerService != null) {
        final res = await widget.printerService!.printSaleTicketAsync(sampleData, openCashDrawer: _ticketAutoDrawer);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.message),
              backgroundColor: res.success ? const Color(0xFF2E7D32) : Colors.orange.shade800,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en impresión de prueba: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingPrinter = false);
    }
  }

  // --- TAB 3: PERMISOS DE CAJEROS ---
  Widget _buildCashierPermissionsTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text(
          'MATRIZ DE PERMISOS PARA CAJEROS',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
        ),
        const Text(
          'Define las acciones autorizadas para el rol cajero sin requerir autorización de supervisor:',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildPermissionTile(
          title: 'Puede aplicar descuentos directos en caja',
          subtitle: 'Permite reducir el precio final de una partida o del ticket completo.',
          value: _permisoDescuentos,
          onChanged: (v) => setState(() => _permisoDescuentos = v),
        ),
        _buildPermissionTile(
          title: 'Puede cancelar ventas completas o partidas',
          subtitle: 'Permite anular tickets emitidos y reintegrar productos al stock.',
          value: _permisoCancelarTickets,
          onChanged: (v) => setState(() => _permisoCancelarTickets = v),
        ),
        _buildPermissionTile(
          title: 'Puede autorizar ventas a crédito',
          subtitle: 'Permite asignar saldo pendiente a clientes con cuenta abierta.',
          value: _permisoDarCredito,
          onChanged: (v) => setState(() => _permisoDarCredito = v),
        ),
        _buildPermissionTile(
          title: 'Puede consultar costos de compra y margen de ganancia',
          subtitle: 'Muestra columnas de costo unitario y porcentaje de utilidad en catálogos.',
          value: _permisoVerCostosCompra,
          onChanged: (v) => setState(() => _permisoVerCostosCompra = v),
        ),
        _buildPermissionTile(
          title: 'Puede registrar entradas y salidas de efectivo',
          subtitle: 'Permite registrar retiros y depósitos menores de caja.',
          value: _permisoMovimientosCaja,
          onChanged: (v) => setState(() => _permisoMovimientosCaja = v),
        ),
        _buildPermissionTile(
          title: 'Puede ejecutar el Corte Z (Cierre definitivo de turno)',
          subtitle: 'Permite cerrar la sesión de caja y generar la discrepancia de arqueo.',
          value: _permisoEjecutarCorteZ,
          onChanged: (v) => setState(() => _permisoEjecutarCorteZ = v),
        ),
        _buildPermissionTile(
          title: 'Puede modificar precios de venta desde el catálogo',
          subtitle: 'Permite alterar los precios base del catálogo.',
          value: _permisoEditarPrecios,
          onChanged: (v) => setState(() => _permisoEditarPrecios = v),
        ),
        _buildPermissionTile(
          title: 'Puede ajustar existencias físicas de inventario',
          subtitle: 'Permite modificar el stock actual sin registrar una compra.',
          value: _permisoModificarStock,
          onChanged: (v) => setState(() => _permisoModificarStock = v),
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        value: value,
        activeThumbColor: const Color(0xFF1F4E79),
        onChanged: onChanged,
      ),
    );
  }

  // --- TAB 4: FACTURACIÓN CFDI ---
  Widget _buildCfdiTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text(
          'PARÁMETROS FISCALES Y FACTURACIÓN ELECTRÓNICA (CFDI)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79)),
        ),
        const Text(
          'Datos fiscales del contribuyente emisor para timbrado digital:',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cfdiRegimenCtrl,
          decoration: const InputDecoration(labelText: 'Régimen Fiscal (SAT) *', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cfdiLugarExpedicionCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lugar de Expedición (C.P.) *', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _cfdiSerieCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Serie de Factura', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _cfdiFolioCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Folio Siguiente', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
