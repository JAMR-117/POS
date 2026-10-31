#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ETL de Migración Histórica desde Firebird (PDVDATA.FDB)
- Cruza ventas históricas con catalogo_migrado_pos.csv (calculando ventas 30d, total unidades y última venta).
- Extrae clientes con sus saldos y límites de crédito a clientes_migrados_pos.csv.
- Sincroniza archivos en C:\POS\migracion\ y C:\POS\client\assets\.
"""

import os
import re
import json
import shutil
from datetime import datetime, timedelta
from collections import defaultdict
import pandas as pd
import firebirdsql

FDB_PATH = r"C:\POS\migracion\PDVDATA.FDB"
CATALOG_PATH = r"C:\POS\migracion\catalogo_migrado_pos.csv"
ASSETS_CATALOG_PATH = r"C:\POS\client\assets\catalogo_migrado_pos.csv"
CLIENTES_CSV_PATH = r"C:\POS\migracion\clientes_migrados_pos.csv"
ASSETS_CLIENTES_PATH = r"C:\POS\client\assets\clientes_migrados_pos.csv"
VENTAS_JSON_PATH = r"C:\POS\migracion\ventas_historicas_clientes.json"
ASSETS_VENTAS_PATH = r"C:\POS\client\assets\ventas_historicas_clientes.json"
ABONOS_JSON_PATH = r"C:\POS\migracion\abonos_historicos_clientes.json"
ASSETS_ABONOS_PATH = r"C:\POS\client\assets\abonos_historicos_clientes.json"

def normalize_key(val):
    if not val or pd.isna(val):
        return ""
    # Strip spaces, symbols, uppercase
    s = re.sub(r'[^A-Z0-9]', '', str(val).strip().upper())
    return s.lstrip('0') if s.lstrip('0') else s

def fix_encoding(text):
    if not text or not isinstance(text, str):
        return text
    try:
        return text.encode('latin-1').decode('utf-8')
    except Exception:
        return text

def main():
    print("=" * 70)
    print("INICIANDO ETL HISTÓRICO DESDE PDVDATA.FDB (FIREBIRD 2.5)")
    print("=" * 70)

    if not os.path.exists(FDB_PATH):
        raise FileNotFoundError(f"No se encontró el archivo FDB en: {FDB_PATH}")

    # 1. Conexión a Firebird
    print(f"[*] Conectando a Firebird en localhost:3050 [{FDB_PATH}]...")
    con = firebirdsql.connect(
        host="localhost",
        port=3050,
        database=FDB_PATH,
        user="SYSDBA",
        password="masterkey",
        charset="WIN1252"
    )
    cur = con.cursor()
    print("[+] Conexión establecida exitosamente.")

    # 2. Obtener fecha máxima global de ventas
    cur.execute("""
        SELECT MAX(a.PAGADO_EN)
        FROM VENTATICKETS_ARTICULOS a
        JOIN VENTATICKETS t ON a.TICKET_ID = t.ID
        WHERE t.ESTA_CANCELADO = 'f'
    """)
    max_fecha_row = cur.fetchone()
    global_max_fecha = max_fecha_row[0] if max_fecha_row and max_fecha_row[0] else datetime.now()
    cutoff_30d = global_max_fecha - timedelta(days=30)
    print(f"[*] Fecha máxima de venta global en BD: {global_max_fecha}")
    print(f"[*] Ventana de 30 días de operación activa: desde {cutoff_30d} hasta {global_max_fecha}")

    # 3. Extraer métricas de ventas por producto
    print("[*] Agrupando historial de ventas por producto...")
    cur.execute("""
        SELECT 
            TRIM(UPPER(a.PRODUCTO_CODIGO)) AS CODIGO,
            SUM(a.CANTIDAD) AS TOTAL_UNIDADES,
            MAX(a.PAGADO_EN) AS ULTIMA_VENTA,
            SUM(CASE WHEN a.PAGADO_EN >= ? THEN a.CANTIDAD ELSE 0 END) AS VENTAS_30D
        FROM VENTATICKETS_ARTICULOS a
        JOIN VENTATICKETS t ON a.TICKET_ID = t.ID
        WHERE t.ESTA_CANCELADO = 'f'
        GROUP BY TRIM(UPPER(a.PRODUCTO_CODIGO))
    """, (cutoff_30d,))

    sales_stats = {}
    total_articulos_fdb = 0
    total_piezas_fdb = 0.0

    for row in cur.fetchall():
        code, total_units, last_sale, sales_30d = row
        if not code:
            continue
        total_units = float(total_units or 0.0)
        sales_30d = float(sales_30d or 0.0)
        last_sale_str = last_sale.strftime('%Y-%m-%d %H:%M:%S') if last_sale else ""
        
        sales_stats[code] = {
            'total_unidades_vendidas': total_units,
            'ultima_venta_at': last_sale_str,
            'ventas_ultimos_30dias': sales_30d
        }
        total_articulos_fdb += 1
        total_piezas_fdb += total_units

    print(f"[+] Total códigos con ventas en FDB: {total_articulos_fdb} ({total_piezas_fdb:,.0f} piezas históricas)")

    # 4. Cruce y enriquecimiento de catalogo_migrado_pos.csv
    print(f"[*] Leyendo catálogo actual desde {CATALOG_PATH}...")
    df_cat = pd.read_csv(CATALOG_PATH, dtype=str)
    
    # Crear índices de búsqueda rápida
    exact_map = {}
    norm_map = {}
    for code, stats in sales_stats.items():
        exact_map[code] = stats
        nkey = normalize_key(code)
        if nkey and nkey not in norm_map:
            norm_map[nkey] = stats

    matched_count = 0
    ventas_30d_col = []
    total_unidades_col = []
    ultima_venta_col = []

    for _, row in df_cat.iterrows():
        cod = str(row.get('codigo', '')).strip().upper()
        sku = str(row.get('sku', '')).strip().upper()
        equiv = str(row.get('codigo_equivalencia', '')).strip().upper()

        stats = None
        # Intentar coincidencia exacta por codigo, sku o equivalencia
        for cand in [cod, sku, equiv]:
            if cand and cand in exact_map:
                stats = exact_map[cand]
                break

        # Si no hubo match exacto, intentar por clave normalizada
        if not stats:
            for cand in [cod, sku, equiv]:
                ncand = normalize_key(cand)
                if ncand and ncand in norm_map:
                    stats = norm_map[ncand]
                    break

        if stats:
            matched_count += 1
            ventas_30d_col.append(stats['ventas_ultimos_30dias'])
            total_unidades_col.append(stats['total_unidades_vendidas'])
            ultima_venta_col.append(stats['ultima_venta_at'])
        else:
            ventas_30d_col.append(0.0)
            total_unidades_col.append(0.0)
            ultima_venta_col.append("")

    df_cat['ventas_ultimos_30dias'] = ventas_30d_col
    df_cat['total_unidades_vendidas'] = total_unidades_col
    df_cat['ultima_venta_at'] = ultima_venta_col

    for text_col in ['nombre', 'descripcion', 'marca', 'departamento']:
        if text_col in df_cat.columns:
            df_cat[text_col] = df_cat[text_col].apply(fix_encoding)

    print(f"[+] Empate exitoso: {matched_count} de {len(df_cat)} productos del catálogo ({matched_count/len(df_cat)*100:.1f}%) tienen métricas históricas de venta.")

    # Guardar catalogo_migrado_pos.csv actualizado
    df_cat.to_csv(CATALOG_PATH, index=False, encoding='utf-8')
    print(f"[+] Archivo guardado: {CATALOG_PATH}")
    
    os.makedirs(os.path.dirname(ASSETS_CATALOG_PATH), exist_ok=True)
    shutil.copy2(CATALOG_PATH, ASSETS_CATALOG_PATH)
    print(f"[+] Sincronizado a assets: {ASSETS_CATALOG_PATH}")

    # 5. Extracción y migración de CLIENTES
    print("[*] Extrayendo clientes desde tabla CLIENTES en PDVDATA.FDB...")
    cur.execute("""
        SELECT 
            NUMERO,
            NOMBRE,
            DIRECCION,
            TELEFONO,
            DSALDOACTUAL,
            LIMITE_CREDITO,
            ULTIMO_PAGO_EN,
            FOLIO
        FROM CLIENTES
        ORDER BY NUMERO
    """)
    client_rows = cur.fetchall()
    clientes_list = []

    for r in client_rows:
        num, nombre, direccion, telefono, saldo, limite, ultimo_pago, folio = r
        nombre_clean = fix_encoding(str(nombre).strip()) if nombre else f"Cliente {num}"
        dir_clean = fix_encoding(str(direccion).strip()) if direccion else ""
        tel_clean = str(telefono).strip() if telefono else ""
        saldo_float = round(float(saldo or 0.0), 2)
        limite_float = round(float(limite or 0.0), 2)
        ultimo_pago_str = ultimo_pago.strftime('%Y-%m-%d %H:%M:%S') if ultimo_pago else ""

        clientes_list.append({
            'id': f"CLI-{num:04d}",
            'nombre': nombre_clean,
            'telefono': tel_clean,
            'email': '',
            'direccion': dir_clean,
            'limite_credito': limite_float,
            'saldo_actual': saldo_float,
            'ultimo_pago_at': ultimo_pago_str,
            'notas': f"Migrado de Eleventa PDVDATA (Folio {folio})" if folio else "Migrado de Eleventa PDVDATA"
        })

    df_clientes = pd.DataFrame(clientes_list)
    df_clientes.to_csv(CLIENTES_CSV_PATH, index=False, encoding='utf-8')
    print(f"[+] Clientes migrados: {len(df_clientes)} guardados en {CLIENTES_CSV_PATH}")
    for _, c in df_clientes.iterrows():
        print(f"    - {c['id']}: {c['nombre']} | Saldo: ${c['saldo_actual']:,.2f} | Límite: ${c['limite_credito']:,.2f} | Tel: {c['telefono']}")

    shutil.copy2(CLIENTES_CSV_PATH, ASSETS_CLIENTES_PATH)
    print(f"[+] Sincronizado a assets: {ASSETS_CLIENTES_PATH}")

    # 6. Extracción de VENTAS HISTÓRICAS DE CLIENTES
    print("[*] Extrayendo tickets históricos atribuidos a clientes...")
    cur.execute("""
        SELECT 
            t.ID,
            t.FOLIO,
            t.CAJA_ID,
            t.CLIENTE_ID,
            c.NOMBRE,
            t.SUBTOTAL,
            t.TOTAL,
            t.ESTA_CANCELADO,
            t.FORMA_PAGO,
            t.PAGADO_EN,
            t.CREADO_EN
        FROM VENTATICKETS t
        JOIN CLIENTES c ON t.CLIENTE_ID = c.NUMERO
        ORDER BY t.PAGADO_EN DESC
    """)
    ticket_rows = cur.fetchall()

    # Obtener artículos por ticket
    cur.execute("""
        SELECT 
            a.ID,
            a.TICKET_ID,
            a.PRODUCTO_CODIGO,
            a.PRODUCTO_NOMBRE,
            a.CANTIDAD,
            a.PRECIO_USADO,
            a.PORCENTAJE_DESCUENTO
        FROM VENTATICKETS_ARTICULOS a
        JOIN VENTATICKETS t ON a.TICKET_ID = t.ID
        WHERE t.CLIENTE_ID IS NOT NULL
        ORDER BY a.ID
    """)
    art_by_ticket = defaultdict(list)
    for r in cur.fetchall():
        art_id, tkt_id, prod_cod, prod_nom, cant, p_usado, desc = r
        clean_cod = str(prod_cod).strip().upper() if prod_cod else ""
        clean_nom = fix_encoding(str(prod_nom).strip()) if prod_nom else clean_cod
        p_flt = round(float(p_usado or 0.0), 2)
        cant_flt = round(float(cant or 1.0), 3)
        tot_flt = round(p_flt * cant_flt, 2)
        art_by_ticket[tkt_id].append({
            'id': f"DET-FDB-{art_id}",
            'producto_id': clean_cod,
            'nombre': clean_nom,
            'cantidad': cant_flt,
            'precio_historico': p_flt,
            'costo_historico': 0.0,
            'descuento_linea': 0.0,
            'total_linea': tot_flt,
        })

    ventas_historicas = []
    for tr in ticket_rows:
        t_id, folio, caja_id, cli_num, cli_nom, subtotal, total, cancelado, forma_pago, pagado_en, creado_en = tr
        fecha_dt = pagado_en or creado_en or datetime.now()
        fecha_iso = fecha_dt.strftime('%Y-%m-%d %H:%M:%S')
        estatus = 'cancelado' if cancelado == 't' else 'completado'
        sub_flt = round(float(subtotal or total or 0.0), 2)
        tot_flt = round(float(total or 0.0), 2)
        cli_id = f"CLI-{cli_num:04d}"
        clean_cli_nom = fix_encoding(str(cli_nom).strip()) if cli_nom else f"Cliente {cli_num}"

        forma_label = 'Crédito' if forma_pago == 'c' else ('Efectivo' if forma_pago == 'e' else ('Tarjeta' if forma_pago == 't' else 'Crédito'))
        pagos = [{'metodo': forma_label, 'monto': tot_flt}]

        items = art_by_ticket.get(t_id, [])

        ventas_historicas.append({
            'id': f"FDB-TKT-{t_id}",
            'corte_caja_id': f"CORTE-FDB-CAJA-{caja_id}",
            'folio_ticket': f"FOLIO-{folio}",
            'cliente_id': cli_id,
            'cliente_nombre': clean_cli_nom,
            'subtotal': sub_flt,
            'descuento_total': 0.0,
            'impuestos_total': 0.0,
            'total': tot_flt,
            'pagos_desglose': json.dumps(pagos),
            'fecha_venta': fecha_iso,
            'estatus': estatus,
            'items': items,
        })

    with open(VENTAS_JSON_PATH, 'w', encoding='utf-8') as f:
        json.dump(ventas_historicas, f, indent=2, ensure_ascii=False)
    shutil.copy2(VENTAS_JSON_PATH, ASSETS_VENTAS_PATH)
    print(f"[+] {len(ventas_historicas)} tickets de clientes guardados en {VENTAS_JSON_PATH} y {ASSETS_VENTAS_PATH}")

    # 7. Extracción de ABONOS HISTÓRICOS
    print("[*] Extrayendo abonos históricos de clientes...")
    cur.execute("""
        SELECT 
            a.ID,
            a.CLIENTE_ID,
            c.NOMBRE,
            a.DTFECHA,
            a.DMONTO
        FROM ABONOS a
        JOIN CLIENTES c ON a.CLIENTE_ID = c.NUMERO
        ORDER BY a.DTFECHA DESC
    """)
    abonos_historicos = []
    for ar in cur.fetchall():
        ab_id, cli_num, cli_nom, fecha, monto = ar
        fecha_iso = fecha.strftime('%Y-%m-%d %H:%M:%S') if fecha else datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        abonos_historicos.append({
            'id': f"ABONO-FDB-{ab_id}",
            'cliente_id': f"CLI-{cli_num:04d}",
            'cliente_nombre': fix_encoding(str(cli_nom).strip()) if cli_nom else f"Cliente {cli_num}",
            'corte_caja_id': "CORTE-FDB-ABONO",
            'monto': round(float(monto or 0.0), 2),
            'fecha': fecha_iso,
        })

    with open(ABONOS_JSON_PATH, 'w', encoding='utf-8') as f:
        json.dump(abonos_historicos, f, indent=2, ensure_ascii=False)
    shutil.copy2(ABONOS_JSON_PATH, ASSETS_ABONOS_PATH)
    print(f"[+] {len(abonos_historicos)} abonos guardados en {ABONOS_JSON_PATH} y {ASSETS_ABONOS_PATH}")

    con.close()
    print("=" * 70)
    print("ETL FINALIZADO CON ÉXITO.")
    print("=" * 70)

if __name__ == "__main__":
    main()
