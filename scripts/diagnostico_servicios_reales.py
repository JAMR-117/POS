# -*- coding: utf-8 -*-
import os
import sys
import pandas as pd
import firebirdsql

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

FDB_PATH = r"C:\POS\migracion\PDVDATA.FDB"
XLS_PATH = r"C:\POS\migracion\inventario_eleventa.xls"

print("=" * 90)
print("DIAGNÓSTICO PROFUNDO DE SERVICIOS, PRECIOS, PILAS Y CLIENTES (ELEVENTA)")
print("=" * 90)

con = firebirdsql.connect(
    host="localhost",
    port=3050,
    database=FDB_PATH,
    user="SYSDBA",
    password="masterkey",
    charset="WIN1252"
)
cur = con.cursor()

# 1. Departamentos
cur.execute("SELECT ID, NOMBRE FROM DEPARTAMENTOS")
deptos = {r[0]: (r[1].strip() if r[1] else "") for r in cur.fetchall()}

# 2. Servicios en PRODUCTOS
print("\n--- SERVICIOS EN CATÁLOGO PRODUCTOS (FDB) ---")
cur.execute("""
    SELECT CODIGO, DESCRIPCION, DEPT, PCOSTO, PVENTA, MAYOREO, TVENTA
    FROM PRODUCTOS
    WHERE DEPT IN (44, 46, 48, 49, 50)
       OR UPPER(DESCRIPCION) CONTAINING 'DUPLICADO'
       OR UPPER(DESCRIPCION) CONTAINING 'SERVICIO'
       OR UPPER(DESCRIPCION) CONTAINING 'APERTURA'
       OR UPPER(DESCRIPCION) CONTAINING 'REPARACION'
       OR UPPER(DESCRIPCION) CONTAINING 'COMBINACION'
       OR UPPER(DESCRIPCION) CONTAINING 'CORTE'
    ORDER BY DEPT, PVENTA DESC
""")
for r in cur.fetchall():
    cod = r[0].strip() if r[0] else ""
    desc = r[1].strip() if r[1] else ""
    did = r[2]
    dname = deptos.get(did, f"ID:{did}")
    pcost = float(r[3] or 0.0)
    pvent = float(r[4] or 0.0)
    pmay = float(r[5] or 0.0)
    print(f"[{cod:15s}] {desc:45s} | Depto: {dname:20s} | Costo: ${pcost:6.2f} | Venta: ${pvent:6.2f} | Mayoreo: ${pmay:6.2f}")

# 3. Precios Históricos Reales en Tickets de Venta
print("\n--- PRECIOS HISTÓRICOS REALES COBRADOS EN VENTATICKETS_ARTICULOS ---")
cur.execute("""
    SELECT 
        TRIM(a.PRODUCTO_CODIGO), 
        TRIM(a.PRODUCTO_NOMBRE),
        AVG(a.PRECIO_USADO),
        MIN(a.PRECIO_USADO),
        MAX(a.PRECIO_USADO),
        SUM(a.CANTIDAD),
        COUNT(*)
    FROM VENTATICKETS_ARTICULOS a
    JOIN VENTATICKETS t ON a.TICKET_ID = t.ID
    WHERE t.ESTA_CANCELADO = 'f'
      AND (
           UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'DUPLICADO'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'SERVICIO'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'CAMBIO'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'APERTURA'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'CORTE'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'PROGRAM'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'HECHURA'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'REPARACION'
        OR UPPER(TRIM(a.PRODUCTO_NOMBRE)) CONTAINING 'COMBINACION'
        OR UPPER(TRIM(a.PRODUCTO_CODIGO)) CONTAINING 'SERV'
        OR UPPER(TRIM(a.PRODUCTO_CODIGO)) CONTAINING 'DUP'
      )
    GROUP BY TRIM(a.PRODUCTO_CODIGO), TRIM(a.PRODUCTO_NOMBRE)
    ORDER BY COUNT(*) DESC
""")
ticket_servs = cur.fetchall()
print(f"Total registros agrupados de servicios vendidos: {len(ticket_servs)}")
for ts in ticket_servs:
    print(f"  Cod: {ts[0]:15s} | Desc: {ts[1]:40s} | Prom: ${ts[2]:7.2f} (Min: ${ts[3]:6.2f}, Max: ${ts[4]:6.2f}) | Qty: {ts[5]:5.0f} | Tickets: {ts[6]:4d}")

# 4. Pilas en Catálogo PRODUCTOS y en Tickets
print("\n--- PILAS / BATERÍAS EN PRODUCTOS (FDB) ---")
cur.execute("""
    SELECT CODIGO, DESCRIPCION, DEPT, PCOSTO, PVENTA, MAYOREO
    FROM PRODUCTOS
    WHERE DEPT = 32
       OR UPPER(DESCRIPCION) CONTAINING 'CR-'
       OR UPPER(DESCRIPCION) CONTAINING 'CR20'
       OR UPPER(DESCRIPCION) CONTAINING 'CR16'
       OR UPPER(DESCRIPCION) CONTAINING 'CR12'
       OR UPPER(DESCRIPCION) CONTAINING '23A'
       OR UPPER(DESCRIPCION) CONTAINING '27A'
    ORDER BY PVENTA DESC
""")
for r in cur.fetchall():
    cod = r[0].strip() if r[0] else ""
    desc = r[1].strip() if r[1] else ""
    did = r[2]
    dname = deptos.get(did, f"ID:{did}")
    pcost = float(r[3] or 0.0)
    pvent = float(r[4] or 0.0)
    pmay = float(r[5] or 0.0)
    print(f"[{cod:15s}] {desc:45s} | Depto: {dname:15s} | Costo: ${pcost:6.2f} | Venta: ${pvent:6.2f} | Mayoreo: ${pmay:6.2f}")

# 5. Clientes y Abonos
print("\n--- CLIENTES, TICKETS HISTÓRICOS Y ABONOS (FDB) ---")
cur.execute("""
    SELECT 
        c.NUMERO, c.NOMBRE, c.DSALDOACTUAL, c.LIMITE_CREDITO,
        COUNT(t.ID) as TOTAL_TICKETS,
        SUM(CASE WHEN t.ESTA_CANCELADO = 'f' THEN t.TOTAL ELSE 0 END) as TOTAL_COMPRADO
    FROM CLIENTES c
    LEFT JOIN VENTATICKETS t ON t.CLIENTE_ID = c.NUMERO
    GROUP BY c.NUMERO, c.NOMBRE, c.DSALDOACTUAL, c.LIMITE_CREDITO
    ORDER BY TOTAL_COMPRADO DESC
""")
for ct in cur.fetchall():
    tot = float(ct[5] or 0.0)
    print(f"  CLI {ct[0]:3d}: {ct[1]:35s} | Saldo: ${ct[2]:8.2f} | Limite: ${ct[3]:8.2f} | Tickets: {ct[4]:4d} | Total: ${tot:10.2f}")

print("\n--- ABONOS HISTÓRICOS EN FDB ---")
cur.execute("""
    SELECT a.ID, a.CLIENTE_ID, c.NOMBRE, a.DTFECHA, a.DMONTO
    FROM ABONOS a
    LEFT JOIN CLIENTES c ON a.CLIENTE_ID = c.NUMERO
    ORDER BY a.DTFECHA DESC
""")
abonos = cur.fetchall()
print(f"Total abonos registrados: {len(abonos)}")
for a in abonos[:15]:
    cli_nom = a[2].strip() if a[2] else f"CLI-{a[1]}"
    print(f"  ID {a[0]}: Cliente {a[1]} ({cli_nom}) | Fecha: {a[3]} | Monto: ${a[4]:.2f}")

con.close()
