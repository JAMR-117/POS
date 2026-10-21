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
import shutil
from datetime import datetime, timedelta
import pandas as pd
import firebirdsql

FDB_PATH = r"C:\POS\migracion\PDVDATA.FDB"
CATALOG_PATH = r"C:\POS\migracion\catalogo_migrado_pos.csv"
ASSETS_CATALOG_PATH = r"C:\POS\client\assets\catalogo_migrado_pos.csv"
CLIENTES_CSV_PATH = r"C:\POS\migracion\clientes_migrados_pos.csv"
ASSETS_CLIENTES_PATH = r"C:\POS\client\assets\clientes_migrados_pos.csv"

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

    con.close()
    print("=" * 70)
    print("ETL FINALIZADO CON ÉXITO.")
    print("=" * 70)

if __name__ == "__main__":
    main()
