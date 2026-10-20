import os
import pandas as pd
import pypdf
import pdfplumber

print("--- 1. INSPECCIONANDO inventario_eleventa.xls ---")
eleventa_path = r"C:\POS\migracion\inventario_eleventa.xls"

df = None
# Intentar xlrd
try:
    df = pd.read_excel(eleventa_path, engine='xlrd')
    print("Leído exitosamente con xlrd!")
except Exception as e:
    print(f"Error con xlrd: {e}")

if df is None:
    try:
        tables = pd.read_html(eleventa_path)
        if tables:
            df = tables[0]
            print(f"Leído exitosamente con read_html! Tablas encontradas: {len(tables)}")
    except Exception as e:
        print(f"Error con read_html: {e}")

if df is None:
    for enc in ['utf-8', 'latin-1', 'cp1252']:
        try:
            df = pd.read_csv(eleventa_path, sep='\t', encoding=enc)
            print(f"Leído exitosamente con read_csv (tsv, {enc})!")
            break
        except Exception as e:
            try:
                df = pd.read_csv(eleventa_path, sep=',', encoding=enc)
                print(f"Leído exitosamente con read_csv (csv, {enc})!")
                break
            except Exception as e2:
                pass

if df is not None:
    print("Shape:", df.shape)
    print("Columnas:", df.columns.tolist())
    print("\nPrimeras 5 filas:")
    print(df.head(5).to_string())
    print("\nMuestra de descripciones aleatorias:")
    desc_col = [c for c in df.columns if 'descrip' in str(c).lower() or 'nombre' in str(c).lower()]
    if desc_col:
        print(df[desc_col[0]].dropna().sample(min(15, len(df))).to_string())
else:
    print("NO SE PUDO LEER EL ARCHIVO XLS!")

print("\n--- 2. INSPECCIONANDO Etiquetas1.pdf ---")
p1_path = r"C:\POS\migracion\Etiquetas1.pdf"
with pdfplumber.open(p1_path) as pdf:
    print(f"Etiquetas1.pdf: {len(pdf.pages)} páginas")
    for idx, page in enumerate(pdf.pages):
        text = page.extract_text()
        print(f"\n--- PÁGINA {idx+1} (primeros 500 caracteres) ---")
        print(text[:500] if text else "VACIO")
        tables = page.extract_tables()
        if tables:
            print(f"Tablas encontradas en página {idx+1}: {len(tables)}")
            for t_idx, table in enumerate(tables):
                print(f"  Tabla {t_idx+1} (primeras 3 filas): {table[:3]}")

print("\n--- 3. INSPECCIONANDO Etiquetas2.pdf ---")
p2_path = r"C:\POS\migracion\Etiquetas2.pdf"
with pdfplumber.open(p2_path) as pdf:
    print(f"Etiquetas2.pdf: {len(pdf.pages)} páginas")
    for idx, page in enumerate(pdf.pages):
        text = page.extract_text()
        print(f"\n--- PÁGINA {idx+1} (primeros 500 caracteres) ---")
        print(text[:500] if text else "VACIO")
        tables = page.extract_tables()
        if tables:
            print(f"Tablas encontradas en página {idx+1}: {len(tables)}")
            for t_idx, table in enumerate(tables):
                print(f"  Tabla {t_idx+1} (primeras 3 filas): {table[:3]}")
