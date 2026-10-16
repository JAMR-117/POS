import 'package:flutter/material.dart';
import '../../data/local/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  bool _isLoading = true;

  // 1. Datos del Negocio
  final TextEditingController _businessNameCtrl = TextEditingController();
  final TextEditingController _businessRfcCtrl = TextEditingController();
  final TextEditingController _businessPhoneCtrl = TextEditingController();
  final TextEditingController _businessAddressCtrl = TextEditingController();
  final TextEditingController _businessSloganCtrl = TextEditingController();

  // 2. Configuración del Ticket Térmico
  final TextEditingController _ticketHeaderCtrl = TextEditingController();
  final TextEditingController _ticketFooterCtrl = TextEditingController();
  String _paperWidth = '80mm'; // '58mm' o '80mm'
  bool _ticketPrintTax = false;
  bool _ticketAutoDrawer = true;

  // 3. Matriz de Permisos para Cajeros (Eleventa Cajeros.png Style)
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _businessNameCtrl.dispose();
    _businessRfcCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessSloganCtrl.dispose();
    _ticketHeaderCtrl.dispose();
    _ticketFooterCtrl.dispose();
    _cfdiRegimenCtrl.dispose();
    _cfdiLugarExpedicionCtrl.dispose();
    _cfdiSerieCtrl.dispose();
    _cfdiFolioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final config = await _dbHelper.getAllConfig();

    _businessNameCtrl.text = config['negocio_nombre'] ?? 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ';
    _businessRfcCtrl.text = config['negocio_rfc'] ?? 'XAXX010101000';
    _businessPhoneCtrl.text = config['negocio_telefono'] ?? '555-123-4567';
    _businessAddressCtrl.text = config['negocio_direccion'] ?? 'Av. Tecnológico #405, Col. Centro';
    _businessSloganCtrl.text = config['negocio_slogan'] ?? 'Especialistas en Llaves, Controles y Aperturas';

    _ticketHeaderCtrl.text = config['ticket_header'] ?? '¡GRACIAS POR SU PREFERENCIA!';
    _ticketFooterCtrl.text = config['ticket_footer'] ?? 'Garantía de duplicados: 30 días presentando este ticket.';
    _paperWidth = config['ticket_ancho_papel'] ?? '80mm';
    _ticketPrintTax = config['ticket_imprimir_impuestos'] == 'true';
    _ticketAutoDrawer = config['ticket_abrir_cajon'] != 'false';

    _permisoDescuentos = config['permiso_cajero_descuentos'] == 'true';
    _permisoCancelarTickets = config['permiso_cajero_cancelar'] == 'true';
    _permisoDarCredito = config['permiso_cajero_credito'] == 'true';
    _permisoVerCostosCompra = config['permiso_cajero_ver_costos'] == 'true';
    _permisoMovimientosCaja = config['permiso_cajero_movimientos'] != 'false';
    _permisoEjecutarCorteZ = config['permiso_cajero_corte_z'] == 'true';
    _permisoEditarPrecios = config['permiso_cajero_editar_precios'] == 'true';
    _permisoModificarStock = config['permiso_cajero_modificar_stock'] == 'true';

    _cfdiRegimenCtrl.text = config['cfdi_regimen_fiscal'] ?? '612 - Personas Físicas con Actividades Empresariales';
    _cfdiLugarExpedicionCtrl.text = config['cfdi_lugar_expedicion'] ?? '76000';
    _cfdiSerieCtrl.text = config['cfdi_serie'] ?? 'A';
    _cfdiFolioCtrl.text = config['cfdi_folio'] ?? '1';

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    await _dbHelper.setConfig('negocio_nombre', _businessNameCtrl.text.trim());
    await _dbHelper.setConfig('negocio_rfc', _businessRfcCtrl.text.trim());
    await _dbHelper.setConfig('negocio_telefono', _businessPhoneCtrl.text.trim());
    await _dbHelper.setConfig('negocio_direccion', _businessAddressCtrl.text.trim());
    await _dbHelper.setConfig('negocio_slogan', _businessSloganCtrl.text.trim());

    await _dbHelper.setConfig('ticket_header', _ticketHeaderCtrl.text.trim());
    await _dbHelper.setConfig('ticket_footer', _ticketFooterCtrl.text.trim());
    await _dbHelper.setConfig('ticket_ancho_papel', _paperWidth);
    await _dbHelper.setConfig('ticket_imprimir_impuestos', _ticketPrintTax.toString());
    await _dbHelper.setConfig('ticket_abrir_cajon', _ticketAutoDrawer.toString());

    await _dbHelper.setConfig('permiso_cajero_descuentos', _permisoDescuentos.toString());
    await _dbHelper.setConfig('permiso_cajero_cancelar', _permisoCancelarTickets.toString());
    await _dbHelper.setConfig('permiso_cajero_credito', _permisoDarCredito.toString());
    await _dbHelper.setConfig('permiso_cajero_ver_costos', _permisoVerCostosCompra.toString());
    await _dbHelper.setConfig('permiso_cajero_movimientos', _permisoMovimientosCaja.toString());
    await _dbHelper.setConfig('permiso_cajero_corte_z', _permisoEjecutarCorteZ.toString());
    await _dbHelper.setConfig('permiso_cajero_editar_precios', _permisoEditarPrecios.toString());
    await _dbHelper.setConfig('permiso_cajero_modificar_stock', _permisoModificarStock.toString());

    await _dbHelper.setConfig('cfdi_regimen_fiscal', _cfdiRegimenCtrl.text.trim());
    await _dbHelper.setConfig('cfdi_lugar_expedicion', _cfdiLugarExpedicionCtrl.text.trim());
    await _dbHelper.setConfig('cfdi_serie', _cfdiSerieCtrl.text.trim());
    await _dbHelper.setConfig('cfdi_folio', _cfdiFolioCtrl.text.trim());

    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración del sistema guardada exitosamente.'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Sistema'),
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
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Guardar Cambios',
            onPressed: _isLoading ? null : _saveSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBusinessDataTab(),
                _buildTicketConfigTab(),
                _buildCashierPermissionsTab(),
                _buildCfdiTab(),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Salir sin Guardar'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F4E79),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: const Icon(Icons.check),
              label: const Text('GUARDAR CONFIGURACIÓN', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _saveSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessDataTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text('INFORMACIÓN GENERAL DEL ESTABLECIMIENTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
        const SizedBox(height: 16),
        TextField(
          controller: _businessNameCtrl,
          decoration: const InputDecoration(labelText: 'Nombre Comercial del Negocio *', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _businessSloganCtrl,
          decoration: const InputDecoration(labelText: 'Lema o Subtítulo Comercial', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _businessRfcCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'RFC del Negocio *', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _businessPhoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp de Contacto', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _businessAddressCtrl,
          decoration: const InputDecoration(labelText: 'Dirección Física del Local', border: OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _buildTicketConfigTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text('DISEÑO Y PARÁMETROS DEL TICKET DE VENTA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Ancho de papel de impresora térmica: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(width: 14),
            ChoiceChip(
              label: const Text('58 mm (Estándar portátil)'),
              selected: _paperWidth == '58mm',
              onSelected: (val) {
                if (val) setState(() => _paperWidth = '58mm');
              },
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: const Text('80 mm (Estándar mostrador)'),
              selected: _paperWidth == '80mm',
              onSelected: (val) {
                if (val) setState(() => _paperWidth = '80mm');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Abrir cajón de dinero automáticamente al cobrar en efectivo'),
          subtitle: const Text('Envía pulso ESC/POS al puerto RJ11 de la impresora térmica.'),
          value: _ticketAutoDrawer,
          activeThumbColor: const Color(0xFF1F4E79),
          onChanged: (val) => setState(() => _ticketAutoDrawer = val),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Imprimir desglose de impuestos (IVA 16%)'),
          subtitle: const Text('Muestra subtotal neto e IVA desglosado en el ticket.'),
          value: _ticketPrintTax,
          activeThumbColor: const Color(0xFF1F4E79),
          onChanged: (val) => setState(() => _ticketPrintTax = val),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ticketHeaderCtrl,
          decoration: const InputDecoration(labelText: 'Encabezado del Ticket (Mensaje de Bienvenida)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ticketFooterCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Pie de Página del Ticket (Políticas de Garantía / Leyendas)', border: OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _buildCashierPermissionsTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text('MATRIZ DE PERMISOS PARA CAJEROS (MODO ESTRICTO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
        const Text('Configura las acciones que los cajeros pueden realizar sin requerir el PIN del administrador:', style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 16),
        _buildPermissionTile(
          title: 'Puede aplicar descuentos manuales en partidas',
          subtitle: 'Permite rebajar el precio o aplicar porcentaje en mostrador.',
          value: _permisoDescuentos,
          onChanged: (v) => setState(() => _permisoDescuentos = v),
        ),
        _buildPermissionTile(
          title: 'Puede cancelar o devolver tickets',
          subtitle: 'Permite anular ventas pasadas o devolver dinero al cliente.',
          value: _permisoCancelarTickets,
          onChanged: (v) => setState(() => _permisoCancelarTickets = v),
        ),
        _buildPermissionTile(
          title: 'Puede fiar / otorgar crédito a clientes',
          subtitle: 'Permite asignar tickets a la cuenta por cobrar de un cliente.',
          value: _permisoDarCredito,
          onChanged: (v) => setState(() => _permisoDarCredito = v),
        ),
        _buildPermissionTile(
          title: 'Puede ver costos de compra y utilidades',
          subtitle: 'Si está desmarcado, el costo de compra y margen permanecen ocultos.',
          value: _permisoVerCostosCompra,
          onChanged: (v) => setState(() => _permisoVerCostosCompra = v),
        ),
        _buildPermissionTile(
          title: 'Puede registrar entradas y salidas de efectivo [F9]',
          subtitle: 'Permite asentar pagos a proveedores o gastos menores de mostrador.',
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
          title: 'Puede modificar precios de venta desde la tabla de productos',
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

  Widget _buildCfdiTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        const Text('PARÁMETROS FISCALES Y FACTURACIÓN ELECTRÓNICA (CFDI)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F4E79))),
        const Text('Datos fiscales del contribuyente emisor para timbrado digital:', style: TextStyle(color: Colors.grey, fontSize: 13)),
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
