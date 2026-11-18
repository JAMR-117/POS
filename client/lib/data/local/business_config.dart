import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';

/// Configuración centralizada del negocio y parámetros del sistema POS.
/// Actúa como Fuente Única de Verdad sincronizada entre SQLite y SharedPreferences.
class BusinessConfig {
  // Datos Comerciales
  final String negocioNombre;
  final String negocioLeyenda;
  final String negocioSlogan;
  final String negocioRfc;
  final String negocioTelefono;
  final String negocioDireccion;
  final String negocioEmail;
  final String? logoBase64;
  final String rutaGuardadoPdf;

  // Mayoreo
  final bool mayoreoAutoEnabled;
  final double mayoreoUmbralGlobal;

  // Crédito Global a Clientes
  final bool creditoClientesHabilitado;

  // Plantilla de Ticket Térmico
  final String ticketHeader;
  final String ticketFooter;
  final String ticketGarantia;
  final String ticketAnchoPapel; // '80mm' | '58mm'
  final String ticketFontFamily; // 'Fuente A' | 'Fuente B' | 'Monospace' | 'Consola'
  final String ticketFontSize; // 'Pequeña' | 'Normal' | 'Mediana' | 'Grande'
  final bool ticketMostrarLogo;
  final bool ticketMostrarNombre;
  final bool ticketMostrarContacto;
  final bool ticketMostrarFolioFecha;
  final bool ticketMostrarCajero;
  final bool ticketMostrarCliente;
  final bool ticketMostrarDescuentosRedondeo;
  final bool ticketMostrarTotalLetra;
  final bool ticketImprimirImpuestos;
  final bool ticketAbrirCajon;
  final bool ticketMostrarCodigoBarras;

  // Permisos de Cajero
  final bool permisoDescuentos;
  final bool permisoCancelarTickets;
  final bool permisoDarCredito;
  final bool permisoVerCostosCompra;
  final bool permisoMovimientosCaja;
  final bool permisoEjecutarCorteZ;
  final bool permisoEditarPrecios;
  final bool permisoModificarStock;

  // Facturación / CFDI
  final String cfdiRegimenFiscal;
  final String cfdiLugarExpedicion;
  final String cfdiSerie;
  final String cfdiFolio;

  const BusinessConfig({
    this.negocioNombre = 'CARprog',
    this.negocioLeyenda = 'Cerrajería y Electrónica Automotriz',
    this.negocioSlogan = 'Especialistas en Llaves con Chip, Controles y Aperturas',
    this.negocioRfc = 'XAXX010101000',
    this.negocioTelefono = '555-123-4567',
    this.negocioDireccion = 'Av. Tecnológico #405, Col. Centro',
    this.negocioEmail = 'contacto@carprog.com',
    this.logoBase64,
    this.rutaGuardadoPdf = r'C:\POS\Cotizaciones',
    this.mayoreoAutoEnabled = true,
    this.mayoreoUmbralGlobal = 5.0,
    this.creditoClientesHabilitado = true,
    this.ticketHeader = '¡GRACIAS POR SU PREFERENCIA!',
    this.ticketFooter = 'La nota original se entregará con la mercancía.',
    this.ticketGarantia = 'Garantía de duplicados y programación: 30 días presentando este comprobante.',
    this.ticketAnchoPapel = '80mm',
    this.ticketFontFamily = 'Fuente A',
    this.ticketFontSize = 'Normal',
    this.ticketMostrarLogo = true,
    this.ticketMostrarNombre = true,
    this.ticketMostrarContacto = true,
    this.ticketMostrarFolioFecha = true,
    this.ticketMostrarCajero = true,
    this.ticketMostrarCliente = true,
    this.ticketMostrarDescuentosRedondeo = true,
    this.ticketMostrarTotalLetra = true,
    this.ticketImprimirImpuestos = false,
    this.ticketAbrirCajon = true,
    this.ticketMostrarCodigoBarras = true,
    this.permisoDescuentos = true,
    this.permisoCancelarTickets = false,
    this.permisoDarCredito = false,
    this.permisoVerCostosCompra = false,
    this.permisoMovimientosCaja = true,
    this.permisoEjecutarCorteZ = false,
    this.permisoEditarPrecios = false,
    this.permisoModificarStock = false,
    this.cfdiRegimenFiscal = '612 - Personas Físicas con Actividades Empresariales',
    this.cfdiLugarExpedicion = '76000',
    this.cfdiSerie = 'A',
    this.cfdiFolio = '1',
  });

  /// Instancia reactiva en memoria compartida por toda la aplicación
  static BusinessConfig current = const BusinessConfig();
  static final ValueNotifier<BusinessConfig> notifier = ValueNotifier<BusinessConfig>(current);

  BusinessConfig copyWith({
    String? negocioNombre,
    String? negocioLeyenda,
    String? negocioSlogan,
    String? negocioRfc,
    String? negocioTelefono,
    String? negocioDireccion,
    String? negocioEmail,
    String? logoBase64,
    String? rutaGuardadoPdf,
    bool? mayoreoAutoEnabled,
    double? mayoreoUmbralGlobal,
    bool? creditoClientesHabilitado,
    String? ticketHeader,
    String? ticketFooter,
    String? ticketGarantia,
    String? ticketAnchoPapel,
    String? ticketFontFamily,
    String? ticketFontSize,
    bool? ticketMostrarLogo,
    bool? ticketMostrarNombre,
    bool? ticketMostrarContacto,
    bool? ticketMostrarFolioFecha,
    bool? ticketMostrarCajero,
    bool? ticketMostrarCliente,
    bool? ticketMostrarDescuentosRedondeo,
    bool? ticketMostrarTotalLetra,
    bool? ticketImprimirImpuestos,
    bool? ticketAbrirCajon,
    bool? ticketMostrarCodigoBarras,
    bool? permisoDescuentos,
    bool? permisoCancelarTickets,
    bool? permisoDarCredito,
    bool? permisoVerCostosCompra,
    bool? permisoMovimientosCaja,
    bool? permisoEjecutarCorteZ,
    bool? permisoEditarPrecios,
    bool? permisoModificarStock,
    String? cfdiRegimenFiscal,
    String? cfdiLugarExpedicion,
    String? cfdiSerie,
    String? cfdiFolio,
  }) {
    return BusinessConfig(
      negocioNombre: negocioNombre ?? this.negocioNombre,
      negocioLeyenda: negocioLeyenda ?? this.negocioLeyenda,
      negocioSlogan: negocioSlogan ?? this.negocioSlogan,
      negocioRfc: negocioRfc ?? this.negocioRfc,
      negocioTelefono: negocioTelefono ?? this.negocioTelefono,
      negocioDireccion: negocioDireccion ?? this.negocioDireccion,
      negocioEmail: negocioEmail ?? this.negocioEmail,
      logoBase64: logoBase64 ?? this.logoBase64,
      rutaGuardadoPdf: rutaGuardadoPdf ?? this.rutaGuardadoPdf,
      mayoreoAutoEnabled: mayoreoAutoEnabled ?? this.mayoreoAutoEnabled,
      mayoreoUmbralGlobal: mayoreoUmbralGlobal ?? this.mayoreoUmbralGlobal,
      creditoClientesHabilitado: creditoClientesHabilitado ?? this.creditoClientesHabilitado,
      ticketHeader: ticketHeader ?? this.ticketHeader,
      ticketFooter: ticketFooter ?? this.ticketFooter,
      ticketGarantia: ticketGarantia ?? this.ticketGarantia,
      ticketAnchoPapel: ticketAnchoPapel ?? this.ticketAnchoPapel,
      ticketFontFamily: ticketFontFamily ?? this.ticketFontFamily,
      ticketFontSize: ticketFontSize ?? this.ticketFontSize,
      ticketMostrarLogo: ticketMostrarLogo ?? this.ticketMostrarLogo,
      ticketMostrarNombre: ticketMostrarNombre ?? this.ticketMostrarNombre,
      ticketMostrarContacto: ticketMostrarContacto ?? this.ticketMostrarContacto,
      ticketMostrarFolioFecha: ticketMostrarFolioFecha ?? this.ticketMostrarFolioFecha,
      ticketMostrarCajero: ticketMostrarCajero ?? this.ticketMostrarCajero,
      ticketMostrarCliente: ticketMostrarCliente ?? this.ticketMostrarCliente,
      ticketMostrarDescuentosRedondeo: ticketMostrarDescuentosRedondeo ?? this.ticketMostrarDescuentosRedondeo,
      ticketMostrarTotalLetra: ticketMostrarTotalLetra ?? this.ticketMostrarTotalLetra,
      ticketImprimirImpuestos: ticketImprimirImpuestos ?? this.ticketImprimirImpuestos,
      ticketAbrirCajon: ticketAbrirCajon ?? this.ticketAbrirCajon,
      ticketMostrarCodigoBarras: ticketMostrarCodigoBarras ?? this.ticketMostrarCodigoBarras,
      permisoDescuentos: permisoDescuentos ?? this.permisoDescuentos,
      permisoCancelarTickets: permisoCancelarTickets ?? this.permisoCancelarTickets,
      permisoDarCredito: permisoDarCredito ?? this.permisoDarCredito,
      permisoVerCostosCompra: permisoVerCostosCompra ?? this.permisoVerCostosCompra,
      permisoMovimientosCaja: permisoMovimientosCaja ?? this.permisoMovimientosCaja,
      permisoEjecutarCorteZ: permisoEjecutarCorteZ ?? this.permisoEjecutarCorteZ,
      permisoEditarPrecios: permisoEditarPrecios ?? this.permisoEditarPrecios,
      permisoModificarStock: permisoModificarStock ?? this.permisoModificarStock,
      cfdiRegimenFiscal: cfdiRegimenFiscal ?? this.cfdiRegimenFiscal,
      cfdiLugarExpedicion: cfdiLugarExpedicion ?? this.cfdiLugarExpedicion,
      cfdiSerie: cfdiSerie ?? this.cfdiSerie,
      cfdiFolio: cfdiFolio ?? this.cfdiFolio,
    );
  }

  /// Carga la configuración completa desde SQLite y complementa con SharedPreferences
  static Future<BusinessConfig> load({DatabaseHelper? dbHelper}) async {
    try {
      final db = dbHelper ?? DatabaseHelper.instance;
      final config = await db.getAllConfig();
      final prefs = await SharedPreferences.getInstance();

      final loaded = BusinessConfig(
        negocioNombre: config['negocio_nombre'] ?? prefs.getString('negocio_nombre') ?? 'CARprog',
        negocioLeyenda: config['negocio_leyenda'] ?? prefs.getString('negocio_leyenda') ?? 'Cerrajería y Electrónica',
        negocioSlogan: config['negocio_slogan'] ?? 'Especialistas en Llaves con Chip, Controles y Aperturas',
        negocioRfc: config['negocio_rfc'] ?? 'XAXX010101000',
        negocioTelefono: config['negocio_telefono'] ?? '555-123-4567',
        negocioDireccion: config['negocio_direccion'] ?? 'Av. Tecnológico #405, Col. Centro',
        negocioEmail: config['negocio_email'] ?? 'contacto@carprog.com',
        logoBase64: config['logo_base64'] ?? prefs.getString('logo_base64'),
        rutaGuardadoPdf: config['ruta_guardado_pdf'] ?? prefs.getString('ruta_guardado_pdf') ?? r'C:\POS\Cotizaciones',
        mayoreoAutoEnabled: config['mayoreo_auto_enabled'] != 'false',
        mayoreoUmbralGlobal: double.tryParse(config['mayoreo_umbral_global'] ?? '') ?? 5.0,
        creditoClientesHabilitado: config['credito_clientes_habilitado'] != 'false',
        ticketHeader: config['ticket_header'] ?? '¡GRACIAS POR SU PREFERENCIA!',
        ticketFooter: config['ticket_footer'] ?? 'La nota original se entregará con la mercancía.',
        ticketGarantia: config['ticket_garantia'] ?? 'Garantía de duplicados: 30 días presentando este ticket.',
        ticketAnchoPapel: config['ticket_ancho_papel'] ?? '80mm',
        ticketFontFamily: config['ticket_font_family'] ?? 'Fuente A',
        ticketFontSize: config['ticket_font_size'] ?? 'Normal',
        ticketMostrarLogo: config['ticket_mostrar_logo'] != 'false',
        ticketMostrarNombre: config['ticket_mostrar_nombre'] != 'false',
        ticketMostrarContacto: config['ticket_mostrar_contacto'] != 'false',
        ticketMostrarFolioFecha: config['ticket_mostrar_folio_fecha'] != 'false',
        ticketMostrarCajero: config['ticket_mostrar_cajero'] != 'false',
        ticketMostrarCliente: config['ticket_mostrar_cliente'] != 'false',
        ticketMostrarDescuentosRedondeo: config['ticket_mostrar_descuentos_redondeo'] != 'false',
        ticketMostrarTotalLetra: config['ticket_mostrar_total_letra'] != 'false',
        ticketImprimirImpuestos: config['ticket_imprimir_impuestos'] == 'true',
        ticketAbrirCajon: config['ticket_abrir_cajon'] != 'false',
        ticketMostrarCodigoBarras: config['ticket_mostrar_codigo_barras'] != 'false',
        permisoDescuentos: config['permiso_cajero_descuentos'] == 'true',
        permisoCancelarTickets: config['permiso_cajero_cancelar'] == 'true',
        permisoDarCredito: config['permiso_cajero_credito'] == 'true',
        permisoVerCostosCompra: config['permiso_cajero_ver_costos'] == 'true',
        permisoMovimientosCaja: config['permiso_cajero_movimientos'] != 'false',
        permisoEjecutarCorteZ: config['permiso_cajero_corte_z'] == 'true',
        permisoEditarPrecios: config['permiso_cajero_editar_precios'] == 'true',
        permisoModificarStock: config['permiso_cajero_modificar_stock'] == 'true',
        cfdiRegimenFiscal: config['cfdi_regimen_fiscal'] ?? '612 - Personas Físicas con Actividades Empresariales',
        cfdiLugarExpedicion: config['cfdi_lugar_expedicion'] ?? '76000',
        cfdiSerie: config['cfdi_serie'] ?? 'A',
        cfdiFolio: config['cfdi_folio'] ?? '1',
      );

      current = loaded;
      notifier.value = loaded;
      return loaded;
    } catch (e) {
      debugPrint('[BusinessConfig] Error al cargar configuración: $e');
      return current;
    }
  }

  /// Guarda atómicamente todos los parámetros en SQLite y SharedPreferences
  Future<void> save({DatabaseHelper? dbHelper}) async {
    final db = dbHelper ?? DatabaseHelper.instance;

    await db.setConfig('negocio_nombre', negocioNombre);
    await db.setConfig('negocio_leyenda', negocioLeyenda);
    await db.setConfig('negocio_slogan', negocioSlogan);
    await db.setConfig('negocio_rfc', negocioRfc);
    await db.setConfig('negocio_telefono', negocioTelefono);
    await db.setConfig('negocio_direccion', negocioDireccion);
    await db.setConfig('negocio_email', negocioEmail);
    await db.setConfig('logo_base64', logoBase64 ?? '');
    await db.setConfig('ruta_guardado_pdf', rutaGuardadoPdf);
    await db.setConfig('mayoreo_auto_enabled', mayoreoAutoEnabled.toString());
    await db.setConfig('mayoreo_umbral_global', mayoreoUmbralGlobal.toString());
    await db.setConfig('credito_clientes_habilitado', creditoClientesHabilitado.toString());

    await db.setConfig('ticket_header', ticketHeader);
    await db.setConfig('ticket_footer', ticketFooter);
    await db.setConfig('ticket_garantia', ticketGarantia);
    await db.setConfig('ticket_ancho_papel', ticketAnchoPapel);
    await db.setConfig('ticket_font_family', ticketFontFamily);
    await db.setConfig('ticket_font_size', ticketFontSize);
    await db.setConfig('ticket_mostrar_logo', ticketMostrarLogo.toString());
    await db.setConfig('ticket_mostrar_nombre', ticketMostrarNombre.toString());
    await db.setConfig('ticket_mostrar_contacto', ticketMostrarContacto.toString());
    await db.setConfig('ticket_mostrar_folio_fecha', ticketMostrarFolioFecha.toString());
    await db.setConfig('ticket_mostrar_cajero', ticketMostrarCajero.toString());
    await db.setConfig('ticket_mostrar_cliente', ticketMostrarCliente.toString());
    await db.setConfig('ticket_mostrar_descuentos_redondeo', ticketMostrarDescuentosRedondeo.toString());
    await db.setConfig('ticket_mostrar_total_letra', ticketMostrarTotalLetra.toString());
    await db.setConfig('ticket_imprimir_impuestos', ticketImprimirImpuestos.toString());
    await db.setConfig('ticket_abrir_cajon', ticketAbrirCajon.toString());
    await db.setConfig('ticket_mostrar_codigo_barras', ticketMostrarCodigoBarras.toString());

    await db.setConfig('permiso_cajero_descuentos', permisoDescuentos.toString());
    await db.setConfig('permiso_cajero_cancelar', permisoCancelarTickets.toString());
    await db.setConfig('permiso_cajero_credito', permisoDarCredito.toString());
    await db.setConfig('permiso_cajero_ver_costos', permisoVerCostosCompra.toString());
    await db.setConfig('permiso_cajero_movimientos', permisoMovimientosCaja.toString());
    await db.setConfig('permiso_cajero_corte_z', permisoEjecutarCorteZ.toString());
    await db.setConfig('permiso_cajero_editar_precios', permisoEditarPrecios.toString());
    await db.setConfig('permiso_cajero_modificar_stock', permisoModificarStock.toString());

    await db.setConfig('cfdi_regimen_fiscal', cfdiRegimenFiscal);
    await db.setConfig('cfdi_lugar_expedicion', cfdiLugarExpedicion);
    await db.setConfig('cfdi_serie', cfdiSerie);
    await db.setConfig('cfdi_folio', cfdiFolio);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('negocio_nombre', negocioNombre);
    await prefs.setString('negocio_leyenda', negocioLeyenda);
    await prefs.setString('logo_base64', logoBase64 ?? '');
    await prefs.setString('ruta_guardado_pdf', rutaGuardadoPdf);
    await prefs.setBool('credito_clientes_habilitado', creditoClientesHabilitado);
    await prefs.setString('ticket_font_family', ticketFontFamily);
    await prefs.setString('ticket_font_size', ticketFontSize);

    current = this;
    notifier.value = this;
  }
}
