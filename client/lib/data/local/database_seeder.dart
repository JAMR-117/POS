import 'package:sqflite/sqflite.dart';

/// Seeder permanente para inicializar el catálogo especializado de Cerrajería,
/// Duplicado de Llaves, Proveeduría y Electrónica Automotriz.
class DatabaseSeeder {
  static Future<void> seed(DatabaseExecutor db) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // 1. Departamentos iniciales
    final List<String> deptos = [
      'Llaves Tradicionales',
      'Cerraduras',
      'Electrónica Automotriz',
      'Servicios',
      'Accesorios y Candados',
      'General'
    ];
    for (final d in deptos) {
      await db.rawInsert('''
        INSERT OR IGNORE INTO departamentos (id, nombre, created_at)
        VALUES ('dep-${d.toLowerCase().replaceAll(' ', '-')}', '$d', '$nowIso');
      ''');
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
        VALUES ('${entry.key}', '${entry.value}', '$nowIso');
      ''');
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
        0.0, 'General', 9999.0, 0.0, 0, NULL, NULL, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 6. Catálogo Especializado de Cerrajería con Multi-Precio y Stock Mínimo
    // -------------------------------------------------------------------------
    // A) Equivalencias de Llaves Tradicionales (Molde Universal EQ-PHI52)
    // -------------------------------------------------------------------------
    // 1. Alba R-52
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-alba-r52', '750000000052', 'R-52', 'Llave Virgen R-52', 
        'Compatible con cerraduras Phillips mod. 715, 5 pernos, latón', 
        'Alba', 'EQ-PHI52', 'Tablero 1 - Gancho 14', 3.50, 15.00, 9.50, 12.00, 
        0.16, 'Llaves Tradicionales', 150.0, 20.0, 0, 10.0, 8.50, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 2. JMA PHI-52
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-jma-phi52', '840000000052', 'PHI-52', 'Llave Virgen PHI-52', 
        'Compatible con cerraduras Phillips mod. 715, 5 pernos', 
        'JMA', 'EQ-PHI52', 'Tablero 1 - Gancho 15', 4.00, 16.00, 10.50, 13.00, 
        0.16, 'Llaves Tradicionales', 80.0, 15.0, 0, 10.0, 9.50, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 3. Ilco 1092
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-ilco-1092', '036000001092', '1092', 'Llave Virgen 1092', 
        'Llave para cerradura Phillips convencional 5 pernos', 
        'Ilco', 'EQ-PHI52', 'Gaveta B-02', 3.80, 15.50, 10.00, 12.50, 
        0.16, 'Llaves Tradicionales', 60.0, 15.0, 0, 10.0, 9.00, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // -------------------------------------------------------------------------
    // B) Llaves y Cerraduras Dexter (Molde Dexter EQ-DX1)
    // -------------------------------------------------------------------------
    // 4. Dexter DX-1
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-dex-dx1', '750000000011', 'DX-1', 'Llave Virgen DX-1', 
        'Llave estándar para cerraduras Dexter', 
        'Dexter', 'EQ-DX1', 'Tablero 2 - Gancho 08', 3.20, 14.00, 9.00, 11.50, 
        0.16, 'Llaves Tradicionales', 120.0, 20.0, 0, 10.0, 8.00, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 5. JMA DEX-1D
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-jma-dex1d', '840000000012', 'DEX-1D', 'Llave Virgen DEX-1D', 
        'Llave compatible con cerraduras Dexter perfil clásico', 
        'JMA', 'EQ-DX1', 'Tablero 2 - Gancho 09', 3.50, 15.00, 9.50, 12.00, 
        0.16, 'Llaves Tradicionales', 75.0, 15.0, 0, 10.0, 8.50, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 6. Cerradura de Pomo Dexter Recámara Latón Brillante
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-dex-cerradura-pomo', '750123456789', 'DX-CP-LB', 'Cerradura de Pomo Dexter Recámara Latón Brillante', 
        'Cerradura cilíndrica de pomo para recámara o entrada, acabado latón brillante', 
        'Dexter', NULL, 'Estante C - Nivel 2', 145.00, 250.00, 195.00, 210.00, 
        0.16, 'Cerraduras', 18.0, 5.0, 0, 5.0, 185.00, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // -------------------------------------------------------------------------
    // C) Electrónica Automotriz / Transpondedores
    // -------------------------------------------------------------------------
    // 7. Transponder Chip TP08 / ID48 Virgen
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-chip-tp08', 'CHIP-TP08-V', 'TP08', 'Transponder Chip TP08 / ID48 Virgen', 
        'Chip cristal Megamos Crypto para VW Jetta A4, Golf, Seat', 
        'Genérica', 'EQ-TP08', 'Gaveta Chips #1', 65.00, 220.00, 130.00, 160.00, 
        0.16, 'Electrónica Automotriz', 35.0, 8.0, 0, 5.0, 110.00, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 8. Llave Hueca con Control VW Flip 3 Botones
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'prod-vw-flip-03', 'VW-FLIP-3B', 'VW-FLIP-03', 'Llave Hueca con Control VW Flip 3 Botones', 
        'Carcasa con control remoto 315MHz compatible VW Jetta A4, Clásico, Beetle', 
        'Xhorse', NULL, 'Vitrina Automotriz A-4', 180.00, 480.00, 320.00, 360.00, 
        0.16, 'Electrónica Automotriz', 12.0, 4.0, 0, 3.0, 290.00, 0, NULL, 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // -------------------------------------------------------------------------
    // D) Servicios Vinculados a Insumos (BOM Ligero con Descuento Automático)
    // -------------------------------------------------------------------------
    // 9. Duplicado Llave Phillips R-52 (Vinculado a Llave Alba R-52)
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'serv-dup-r52', 'SRV-DUP-R52', 'SERV-R52', 'Servicio Duplicado Llave Phillips R-52', 
        'Corte y duplicado de llave tradicional Phillips perfil R52', 
        'Taller', NULL, 'Área de Máquinas', 4.50, 35.00, 20.00, 25.00, 
        0.16, 'Servicios', 999.0, 0.0, 0, 10.0, 18.00, 1, 'prod-alba-r52', 1.0, '$nowIso', '$nowIso'
      );
    ''');

    // 10. Programación y Corte Chip VW ID48 (Vinculado a Transponder TP08)
    await db.rawInsert('''
      INSERT OR IGNORE INTO productos (
        id, codigo_barras, sku, nombre, descripcion, marca, codigo_equivalencia, 
        ubicacion, precio_compra, precio_venta, precio_cerrajero, precio_taller, 
        porcentaje_impuesto, departamento, stock_actual, stock_minimo, es_a_granel, 
        cantidad_mayoreo, precio_mayoreo, es_servicio, insumo_vinculado_id, cantidad_insumo, created_at, updated_at
      ) VALUES (
        'serv-prog-id48', 'SRV-PROG-ID48', 'SERV-ID48', 'Servicio Programación y Corte Chip VW ID48', 
        'Corte de espada regata + programación y hermanado de transponder TP08 en Jetta A4/Seat', 
        'Taller', NULL, 'Mesa de Diagnóstico / OBD', 65.00, 850.00, 500.00, 600.00, 
        0.16, 'Servicios', 999.0, 0.0, 0, 2.0, 450.00, 1, 'prod-chip-tp08', 1.0, '$nowIso', '$nowIso'
      );
    ''');
  }
}
