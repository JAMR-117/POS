import csv
import firebird.driver as fdb

con = fdb.connect(
    database=r'C:\Julián\db\PDVDATA.FDB',
    user='SYSDBA',
    password='masterkey',
    charset='NONE'
)
cur = con.cursor()
cur.execute("SELECT TRIM(CODIGO_BARRAS), TRIM(DESCRIPCION), PRECIO_COSTO, PRECIO_VENTA, EXISTENCIA FROM ARTICULOS WHERE ACTIVO = 1")

with open(r'C:\POS\catalogo_extraido.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['codigo', 'descripcion', 'precio_compra', 'precio_venta', 'stock'])
    for r in cur.fetchall():
        w.writerow([r[0], r[1], float(r[2] or 0.0), float(r[3] or 0.0), float(r[4] or 0.0)])

con.close()
print("Catálogo extraído con éxito en C:\\POS\\catalogo_extraido.csv")