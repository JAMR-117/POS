import 'package:sqflite/sqflite.dart';
import '../../core/department_theme.dart';

/// Seeder permanente para inicializar el catálogo especializado de Cerrajería,
/// Duplicado de Llaves, Proveeduría y Electrónica Automotriz.
class DatabaseSeeder {
  static Future<void> seed(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // 1. Departamentos estandarizados oficiales (9 categorías limpias)
    for (final d in kAllStandardDepartments) {
      final depId = 'dep-${d.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
      await db.rawInsert('''
        INSERT OR IGNORE INTO departamentos (id, nombre, created_at)
        VALUES (?, ?, ?);
      ''', [depId, d, nowIso]);
    }

    // 2. Configuración predeterminada del Negocio
    final Map<String, String> defaultConfig = {
      'negocio_nombre': 'CERRAJERÍA Y ELECTRÓNICA AUTOMOTRIZ',
      'negocio_logo': '',
      'negocio_rfc': 'CARP901016ABC',
      'negocio_direccion': 'Av. Principal #102, Col. Centro',
      'negocio_telefono': '+52 (55) 1234-5678',
      'negocio_email': 'contacto@cerrajeriapos.com',
      'ticket_encabezado': '¡Expertos en Duplicados, Cerraduras y Llaves con Chip!',
      'ticket_pie': 'Garantía de 30 días en duplicados y programación con ticket.',
      'ticket_ancho': '80', // 80mm
      'facturacion_serie': 'A',
      'facturacion_regimen': '612 - Personas Físicas con Actividades Empresariales',
      'facturacion_cp': '06000',
    };

    for (final entry in defaultConfig.entries) {
      await db.rawInsert('''
        INSERT OR IGNORE INTO configuracion_negocio (key, value, updated_at)
        VALUES (?, ?, ?);
      ''', [entry.key, entry.value, nowIso]);
    }

    // 3. Usuarios del sistema POS (RBAC y permisos estilo Eleventa)
    await db.rawInsert('''
      INSERT OR IGNORE INTO usuarios (id, nombre, pin_acceso, rol, permisos, activo) 
      VALUES ('admin-001', 'Administrador Principal', '1234', 'admin', '{"ventas_cobrar":true,"ventas_art_comun":true,"ventas_entradas":true,"ventas_salidas":true,"ventas_precios":true,"ventas_historial":true,"ventas_credito":true,"inv_agregar":true,"inv_existencias":true,"inv_ajustar":true,"inv_movimientos":true,"prod_crear":true,"prod_modificar":true,"prod_eliminar":true,"prod_reporte":true,"prod_departamentos":true,"cli_credito":true,"cli_gestionar":true,"otros_config":true,"otros_corte":true,"otros_ganancia":true}', 1);
    ''');
    await db.rawInsert('''
      INSERT OR IGNORE INTO usuarios (id, nombre, pin_acceso, rol, permisos, activo) 
      VALUES ('cajero-001', 'Caja 1', '5678', 'cajero', '{"ventas_cobrar":true,"ventas_art_comun":true,"ventas_entradas":true,"ventas_salidas":false,"ventas_precios":true,"ventas_historial":true,"ventas_credito":false,"inv_agregar":false,"inv_existencias":true,"inv_ajustar":false,"inv_movimientos":false,"prod_crear":false,"prod_modificar":false,"prod_eliminar":false,"prod_reporte":false,"prod_departamentos":false,"cli_credito":false,"cli_gestionar":false,"otros_config":false,"otros_corte":true,"otros_ganancia":false}', 1);
    ''');

    // 3.1 Cortes de caja base para trazabilidad histórica y arranque
    await db.rawInsert('''
      INSERT OR IGNORE INTO cortes_caja (
        id, folio_corte, usuario_id, monto_inicial, monto_ventas_efectivo,
        monto_ventas_tarjeta, monto_ventas_otros, monto_retiros, tipo_corte,
        discrepancia, fecha_apertura, fecha_cierre, estado
      ) VALUES (
        'CORTE-FDB-CAJA-1', 1, 'admin-001', 0.0, 0.0,
        0.0, 0.0, 0.0, 'Z',
        0.0, '$nowIso', '$nowIso', 'cerrado'
      );
    ''');
    await db.rawInsert('''
      INSERT OR IGNORE INTO cortes_caja (
        id, folio_corte, usuario_id, monto_inicial, monto_ventas_efectivo,
        monto_ventas_tarjeta, monto_ventas_otros, monto_retiros, tipo_corte,
        discrepancia, fecha_apertura, fecha_cierre, estado
      ) VALUES (
        'CORTE-FDB-ABONO', 2, 'admin-001', 0.0, 0.0,
        0.0, 0.0, 0.0, 'Z',
        0.0, '$nowIso', '$nowIso', 'cerrado'
      );
    ''');

    // 4. Clientes predeterminados en caja
    await db.rawInsert('''
      INSERT OR IGNORE INTO clientes (
        id, nombre, rfc_o_dni, regimen_fiscal, uso_cfdi, codigo_postal, 
        correo, telefono, direccion, limite_credito, saldo_deudor, tarifa_preferencial, activo, created_at
      ) VALUES (
        'PUBLICO-GRAL', 'Público en General', 'XAXX010101000', '616', 'S01', '00000',
        'cliente@mostrador.com', '5500000000', 'Venta en Mostrador', 0.0, 0.0, 'Público', 1, '$nowIso'
      );
    ''');

    await db.rawInsert('''
      INSERT OR IGNORE INTO clientes (
        id, nombre, rfc_o_dni, regimen_fiscal, uso_cfdi, codigo_postal, 
        correo, telefono, direccion, limite_credito, saldo_deudor, tarifa_preferencial, activo, created_at
      ) VALUES (
        'cli-cerrajero-juan', 'Cerrajero Juan (Taller Los Álamos)', 'JUAP850312XYZ', '612', 'G03', '06010',
        'cerrajerojuan@gmail.com', '5511223344', 'Calle Cedros 45', 2500.0, 350.0, 'Cerrajero', 1, '$nowIso'
      );
    ''');

    await db.rawInsert('''
      INSERT OR IGNORE INTO clientes (
        id, nombre, rfc_o_dni, regimen_fiscal, uso_cfdi, codigo_postal, 
        correo, telefono, direccion, limite_credito, saldo_deudor, tarifa_preferencial, activo, created_at
      ) VALUES (
        'cli-taller-automotriz', 'Taller Mecánico & Eléctrico Rápido', 'TER991201KL5', '601', 'G03', '06020',
        'taller.rapido@gmail.com', '5599887766', 'Av. Insurgentes Sur 890', 5000.0, 1200.0, 'Taller', 1, '$nowIso'
      );
    ''');

    // 5. Artículo Común para cobros rápidos no catalogados
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'ART-COMUN', 'ART-COMUN', 'ART-COMUN', 'Artículo Común', 'Artículo o cobro misceláneo directo en caja', 
        'Genérica', NULL, 'Caja', 0.0, 0.0, 0.0, 0.0, 
        0.0, 'Herramientas y Accesorios', 9999.0, 0.0, 0, NULL, NULL, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 6. Servicios Maestros Configurables por Departamento (garantizados en todo arranque)
    final masterServices = <Map<String, dynamic>>[
      {
        'id': 'SRV-CAM-PILA',
        'nombre': 'Cambio / Instalación de Pila en Control',
        'desc': 'Instalación profesional de batería de litio, verificación de voltaje y prueba de emisión RF',
        'deptos': 'Pilas y Baterías,Controles y Carcasas',
        'pv': 80.0,
        'pc': 50.0,
        'pt': 60.0,
        'pm': 60.0,
        'cm': 5.0,
      },
      {
        'id': 'SRV-CAM-CAR',
        'nombre': 'Cambio de Carcasa / Adaptación',
        'desc': 'Sustitución de carcasa automotriz, trasplante de tableta electrónica y adaptación de espadín',
        'deptos': 'Controles y Carcasas',
        'pv': 250.0,
        'pc': 150.0,
        'pt': 200.0,
        'pm': 180.0,
        'cm': 3.0,
      },
      {
        'id': 'SRV-REP-CTRL',
        'nombre': 'Reparación de Control / Soldadura de Microswitch / Botón',
        'desc': 'Reparación electrónica de circuito impreso de control remoto, microswitches y soldadura SMD',
        'deptos': 'Controles y Carcasas',
        'pv': 50.0,
        'pc': 30.0,
        'pt': 35.0,
        'pm': 35.0,
        'cm': 5.0,
      },
      {
        'id': 'SRV-PROG-CTRL',
        'nombre': 'Programación de Control / Telemando',
        'desc': 'Generación y programación inalámbrica de control remoto telemando o llave de proximidad',
        'deptos': 'Controles y Carcasas,Automotriz',
        'pv': 500.0,
        'pc': 350.0,
        'pt': 400.0,
        'pm': 400.0,
        'cm': 2.0,
      },
      {
        'id': 'SRV-PROG-CHIP',
        'nombre': 'Programación de Transponder / Chip',
        'desc': 'Programación por OBDII o clonación de chip transponder inmovilizador automotriz',
        'deptos': 'Transponders y Chips,Automotriz',
        'pv': 500.0,
        'pc': 350.0,
        'pt': 400.0,
        'pm': 400.0,
        'cm': 2.0,
      },
      {
        'id': 'SRV-DUP-RES',
        'nombre': 'Duplicado de Llave Residencial / Tradicional',
        'desc': 'Servicio de corte y duplicado para llave residencial tradicional, chapa doméstica o candado',
        'deptos': 'Residencial',
        'pv': 20.0,
        'pc': 15.0,
        'pt': 17.0,
        'pm': 16.0,
        'cm': 5.0,
      },
      {
        'id': 'SRV-DUP-SEG',
        'nombre': 'Duplicado de Llave de Seguridad / Punto',
        'desc': 'Servicio de corte de llave multipunto, alta seguridad, tetra o tubular',
        'deptos': 'Seguridad / Punto',
        'pv': 60.0,
        'pc': 45.0,
        'pt': 50.0,
        'pm': 50.0,
        'cm': 5.0,
      },
      {
        'id': 'SRV-DUP-AUT',
        'nombre': 'Duplicado / Corte de Llave Automotriz',
        'desc': 'Servicio de corte mecánico o regata láser para llave automotriz hueca o con forja',
        'deptos': 'Automotriz',
        'pv': 50.0,
        'pc': 30.0,
        'pt': 35.0,
        'pm': 35.0,
        'cm': 3.0,
      },
      {
        'id': 'SRV-DUP-MOT',
        'nombre': 'Duplicado de Llave para Moto',
        'desc': 'Servicio de corte y duplicado de llave para motocicleta o motoneta',
        'deptos': 'Motos',
        'pv': 35.0,
        'pc': 20.0,
        'pt': 25.0,
        'pm': 25.0,
        'cm': 3.0,
      },
      {
        'id': 'SRV-GEN-CERO',
        'nombre': 'Generación de Llave desde Cero',
        'desc': 'Elaboración, lectura de combinación, corte y programación por pérdida total',
        'deptos': 'Automotriz,Cerraduras y Candados,Motos',
        'pv': 1200.0,
        'pc': 800.0,
        'pt': 1000.0,
        'pm': 900.0,
        'cm': 2.0,
      },
      {
        'id': 'SRV-APER-COMB',
        'nombre': 'Servicio de Apertura / Cambio de Combinación / Reparación de Cerradura',
        'desc': 'Apertura técnica, cambio o igualación de combinación y reparación de cerrajería en taller o campo',
        'deptos': 'Cerraduras y Candados,Residencial,Automotriz,Seguridad / Punto',
        'pv': 250.0,
        'pc': 180.0,
        'pt': 200.0,
        'pm': 200.0,
        'cm': 3.0,
      },
    ];

    for (final s in masterServices) {
      await db.rawInsert('''
        INSERT OR IGNORE INTO productos (
          id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia,
          ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller,
          porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel,
          cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 'Taller', NULL, NULL, 0.0, ?, ?, ?, 0.0, 'Servicios', 999.0, 0.0, 0, ?, ?, 1, NULL, 1.0, ?, ?);
      ''', [
        s['id'],
        s['id'],
        s['id'],
        s['nombre'],
        s['desc'],
        s['pv'],
        s['pc'],
        s['pt'],
        s['cm'],
        s['pm'],
        nowIso,
        nowIso,
      ]);

      try {
        await db.rawUpdate('''
          UPDATE productos 
          SET nombre = ?, descripcion = ?, precio_venta = ?, precio_cerrajero = ?, precio_taller = ?, precio_mayoreo = ?, departamentos_aplicables = ?
          WHERE id = ?;
        ''', [
          s['nombre'],
          s['desc'],
          s['pv'],
          s['pc'],
          s['pt'],
          s['pm'],
          s['deptos'],
          s['id'],
        ]);
      } catch (_) {}
    }
  }
}
