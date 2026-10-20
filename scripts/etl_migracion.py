import os
import sys
import re
from collections import defaultdict
import pandas as pd
import pdfplumber

if sys.stdout.encoding.lower() != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

def main():
    print("=" * 80)
    print("      INICIO DE PROCESO ETL: MIGRACION INTELIGENTE DE CATALOGO POS")
    print("=" * 80)

    migracion_dir = r"C:\POS\migracion"
    eleventa_path = os.path.join(migracion_dir, "inventario_eleventa.xls")
    pdf1_path = os.path.join(migracion_dir, "Etiquetas1.pdf")
    pdf2_path = os.path.join(migracion_dir, "Etiquetas2.pdf")

    # -------------------------------------------------------------------------
    # 1. LECTURA ROBUSTA DE inventario_eleventa.xls
    # -------------------------------------------------------------------------
    print("\n[1/5] Leyendo archivo crudo:", eleventa_path)
    df_raw = None
    read_method = ""

    # Intento 1: xlrd (Excel binario BIFF8)
    try:
        df_raw = pd.read_excel(eleventa_path, engine='xlrd')
        read_method = "pd.read_excel (engine=xlrd)"
    except Exception as e:
        print(f"  - Nota: xlrd no pudo leer el archivo ({e}). Probando fallbacks...")

    # Intento 2: read_html
    if df_raw is None:
        try:
            tables = pd.read_html(eleventa_path)
            if tables:
                df_raw = tables[0]
                read_method = "pd.read_html"
        except Exception as e:
            print(f"  - Nota: read_html falló ({e}). Probando TSV/CSV...")

    # Intento 3: read_csv (TSV / CSV con encodings utf-8 o latin-1)
    if df_raw is None:
        for enc in ['latin-1', 'utf-8', 'cp1252']:
            for sep in ['\t', ',']:
                try:
                    df_raw = pd.read_csv(eleventa_path, sep=sep, encoding=enc)
                    if len(df_raw.columns) > 1:
                        read_method = f"pd.read_csv (sep='{sep}', encoding='{enc}')"
                        break
                except Exception:
                    continue
            if df_raw is not None and len(df_raw.columns) > 1:
                break

    if df_raw is None:
        raise RuntimeError("ERROR CRÍTICO: No se pudo leer inventario_eleventa.xls con ningún método soportado.")

    print(f"  [OK] Archivo leído con éxito mediante: {read_method}")
    print(f"  [OK] Registros brutos encontrados: {len(df_raw)}")
    print(f"  [OK] Columnas detectadas: {df_raw.columns.tolist()}")

    # Normalizar nombres de columnas de Eleventa
    col_mapping = {}
    for col in df_raw.columns:
        c_clean = str(col).strip().lower()
        if 'inventario' in c_clean or 'existencia' in c_clean or 'stock' in c_clean:
            if 'minimo' in c_clean or 'mínimo' in c_clean:
                col_mapping[col] = 'inv_minimo_raw'
            else:
                col_mapping[col] = 'stock_raw'
        elif 'codigo' in c_clean or 'código' in c_clean or 'clave' in c_clean:
            col_mapping[col] = 'codigo_raw'
        elif 'descrip' in c_clean or 'nombre' in c_clean:
            col_mapping[col] = 'descripcion_raw'
        elif 'costo' in c_clean or 'compra' in c_clean:
            col_mapping[col] = 'costo_raw'
        elif 'mayoreo' in c_clean:
            col_mapping[col] = 'mayoreo_raw'
        elif 'venta' in c_clean or 'precio' in c_clean:
            col_mapping[col] = 'venta_raw'
        elif 'depto' in c_clean or 'departamento' in c_clean or 'categoria' in c_clean:
            col_mapping[col] = 'depto_raw'

    df = df_raw.rename(columns=col_mapping)
    print("  [OK] Columnas normalizadas:", list(df.columns))

    # Limpiar strings
    df['codigo_raw'] = df['codigo_raw'].astype(str).str.strip()
    df['descripcion_raw'] = df['descripcion_raw'].astype(str).str.strip()
    if 'depto_raw' in df.columns:
        df['depto_raw'] = df['depto_raw'].astype(str).str.strip()
    else:
        df['depto_raw'] = 'General'

    # -------------------------------------------------------------------------
    # 2. EXTRACCIÓN Y PARSEO DE Etiquetas1.pdf Y Etiquetas2.pdf
    # -------------------------------------------------------------------------
    print("\n[2/5] Extrayendo y estructurando etiquetas desde PDFs...")

    def parse_pdf_labels():
        pdf_labels = [] # Lista de tuplas: (ubicacion_normalizada, texto_contenido, fuente_pdf)

        # Parsear Etiquetas1.pdf
        if os.path.exists(pdf1_path):
            with pdfplumber.open(pdf1_path) as p1:
                for pno, page in enumerate(p1.pages):
                    text = page.extract_text() or ''
                    # Capturar (AUxx), (MOxx), (RExx), (SExx), etc.
                    matches = list(re.finditer(r'\(((?:AU|RE|SE|MO|Mt)\s*\d+[\w/-]*)\)', text, re.I))
                    for i, m in enumerate(matches):
                        loc_raw = m.group(1).strip()
                        start = m.end()
                        end = matches[i+1].start() if i+1 < len(matches) else len(text)
                        content = text[start:end].strip()
                        content = re.sub(r'\s+', ' ', content)
                        if content and '[uncataloged]' not in content.lower():
                            pdf_labels.append((loc_raw, content, "Etiquetas1.pdf"))

        # Parsear Etiquetas2.pdf (desde tablas y texto)
        if os.path.exists(pdf2_path):
            with pdfplumber.open(pdf2_path) as p2:
                for pno, page in enumerate(p2.pages):
                    tables = page.extract_tables()
                    for tbl in tables:
                        for row in tbl:
                            for cell in row:
                                if not cell: continue
                                cell_str = str(cell).strip()
                                m = re.search(r'\(((?:AU|RE|SE|MO|Mt)\s*\d+[\w/-]*)\)\s*(.*)', cell_str, re.I | re.S)
                                if m:
                                    loc_raw = m.group(1).strip()
                                    content = re.sub(r'\s+', ' ', m.group(2).strip())
                                    if content and '[uncataloged]' not in content.lower():
                                        pdf_labels.append((loc_raw, content, "Etiquetas2.pdf"))

        return pdf_labels

    pdf_labels = parse_pdf_labels()
    print(f"  [OK] Total de etiquetas extraídas de ambos PDFs: {len(pdf_labels)}")
    print("  Muestra de etiquetas capturadas (primeras 10):")
    for loc, content, src in pdf_labels[:10]:
        print(f"    [{src}] ({loc}) -> {content}")

    # Normalizar ubicación: ej. AU01 -> AU-01, Au35 -> AU-35, Mt10 -> MO-10, RE73 -> RE-73
    def format_location_code(loc_str):
        if not loc_str:
            return None
        m = re.match(r'^(AU|RE|SE|MO|Mt)\s*(\d+[\w/-]*)$', loc_str.strip(), re.I)
        if m:
            prefix = m.group(1).upper()
            if prefix == 'MT':
                prefix = 'MO'
            num_part = m.group(2).strip().upper()
            return f"{prefix}-{num_part}"
        return loc_str.strip().upper()

    def get_dept_from_loc(loc_norm):
        if not loc_norm:
            return None
        if loc_norm.startswith('AU-'):
            return 'Automotriz'
        elif loc_norm.startswith('RE-'):
            return 'Residencial'
        elif loc_norm.startswith('SE-'):
            return 'Seguridad / Punto'
        elif loc_norm.startswith('MO-'):
            return 'Motos'
        return None

    # Estructurar mapa de llaves de los PDFs para matching rápido
    # Una etiqueta puede contener múltiples claves: ej. 'F2E|FO-8D', 'IK2P/ITA-2P', 'A81E/P'
    pdf_key_map = {} # token_limpio -> { 'ubicacion': ..., 'departamento': ..., 'raw_content': ..., 'source': ... }

    def clean_key_token(t):
        return re.sub(r'[^A-Z0-9]', '', str(t).upper())

    for loc_raw, content, src in pdf_labels:
        loc_norm = format_location_code(loc_raw)
        dept = get_dept_from_loc(loc_norm)

        # Desglosar claves del contenido
        subtokens = []
        if '|' in content:
            subtokens.extend([x.strip() for x in content.split('|')])
        elif '/' in content:
            # ej. A81E/P -> A81E, A81EP | HOND-20D/P -> HOND-20D, HOND-20DP | NE-20 / NE-36
            parts = [x.strip() for x in content.split('/')]
            base = parts[0]
            subtokens.append(base)
            for p in parts[1:]:
                if len(p) <= 2 and p.isalpha():
                    subtokens.append(base + p)
                else:
                    subtokens.append(p)
        else:
            # Dividir por espacios si contiene múltiples palabras que parecen claves
            # ej. 'BAJ-4AP PULSAR', 'HK-HONDA-ANT', 'VA-34 Aveo'
            words = content.split()
            if words:
                subtokens.append(words[0])
                if len(words) > 1 and len(words[1]) >= 3 and not words[1].lower() in ['p', 'pulsar', 'aveo', 'spark']:
                    subtokens.append(words[1])
            subtokens.append(content)

        for st in subtokens:
            tok = clean_key_token(st)
            if tok and len(tok) >= 2:
                pdf_key_map[tok] = {
                    'ubicacion': loc_norm,
                    'departamento': dept,
                    'raw_content': content,
                    'source': src,
                    'key_candidate': st
                }

    print(f"  [OK] Tokens indexados desde PDFs para cruce prioritario: {len(pdf_key_map)}")

    # -------------------------------------------------------------------------
    # 3. EXTRACCIÓN DE UBICACIÓN DESDE DESCRIPCIONES Y CRUCE PRIORITARIO CON PDF
    # -------------------------------------------------------------------------
    print("\n[3/5] Extrayendo ubicaciones de Eleventa y aplicando cruce prioritario con PDFs...")

    updated_from_pdf_count = 0
    extracted_from_desc_count = 0

    ubicaciones_finales = []
    deptos_finales = []
    descripciones_limpias = []
    nombres_finales = []

    regex_loc_paren = re.compile(r'\(((?:AU|RE|SE|MO|Mt)\s*\d+[\w/-]*)\)', re.I)

    for idx, row in df.iterrows():
        cod_raw = row['codigo_raw']
        desc_raw = row['descripcion_raw']
        depto_orig = row['depto_raw']

        # 1. Ubicación base desde la descripción de Eleventa
        loc_desc = None
        m_loc = regex_loc_paren.search(desc_raw)
        if m_loc:
            loc_desc = format_location_code(m_loc.group(1))

        # 2. Verificar coincidencia prioritaria con PDFs
        loc_final = loc_desc
        dept_final = get_dept_from_loc(loc_desc)
        matched_from_pdf = False

        # Tokens a verificar del producto: código exacto, base sin DUP, y tokens de la descripción
        tokens_to_test = [clean_key_token(cod_raw)]
        cod_no_dup = re.sub(r'\s+DUP$', '', cod_raw, flags=re.I).strip()
        tokens_to_test.append(clean_key_token(cod_no_dup))

        # Tokens de descripción entre paréntesis o palabras
        for p in re.findall(r'\(([^)]+)\)', desc_raw):
            tokens_to_test.append(clean_key_token(p))

        # Verificar si algún token coincide con los PDFs
        for tok in tokens_to_test:
            if tok in pdf_key_map:
                pdf_info = pdf_key_map[tok]
                loc_final = pdf_info['ubicacion']
                if pdf_info['departamento']:
                    dept_final = pdf_info['departamento']
                matched_from_pdf = True
                break

        if not matched_from_pdf and loc_final is None:
            # Buscar coincidencia difusa en nombres de huecas (ej. HK-HONDA-A con HK-HONDA-ANT)
            for p_tok, pdf_info in pdf_key_map.items():
                if len(p_tok) >= 5 and p_tok in clean_key_token(cod_raw) or (clean_key_token(cod_raw) and clean_key_token(cod_raw) in p_tok):
                    loc_final = pdf_info['ubicacion']
                    if pdf_info['departamento']:
                        dept_final = pdf_info['departamento']
                    matched_from_pdf = True
                    break

        if matched_from_pdf:
            updated_from_pdf_count += 1
        elif loc_final is not None:
            extracted_from_desc_count += 1

        # Si aún no tiene departamento asignado por ubicación, asignar según categoría de Eleventa
        if not dept_final:
            depto_upper = depto_orig.upper()
            if any(s in depto_upper for s in ['DUPLICADO', 'REPARACION', 'SERVICIO', 'PROGRAMACION']):
                dept_final = 'Servicios'
            elif 'CANDADO' in depto_upper:
                dept_final = 'Candados'
            elif 'CERRADURA' in depto_upper or 'CILINDRO' in depto_upper:
                dept_final = 'Cerraduras'
            elif any(h in depto_upper for h in ['HERRAMIENTA', 'LIMA', 'CORTADOR', 'GANZUA']):
                dept_final = 'Herramientas'
            elif any(a in depto_upper for a in ['CARCAZA', 'TRANSPONDER', 'HERRAJE', 'VVDI', 'KD', 'INSERTOS', 'CONTROL']):
                dept_final = 'Automotriz'
            elif 'PILA' in depto_upper:
                dept_final = 'Accesorios / Pilas'
            elif 'FORJA' in depto_upper:
                # Determinar si la forja es automotriz, residencial o moto
                d_u = desc_raw.upper()
                c_u = cod_raw.upper()
                if any(m in d_u or m in c_u for m in ['MOTO', 'PULSAR', 'ITALIKA', 'YAMAHA', 'HONDA MOTO', 'BAJAJ']):
                    dept_final = 'Motos'
                elif any(au in d_u or au in c_u for au in ['AUTO', 'NISSAN', 'FORD', 'CHEVY', 'VW', 'GM', 'CHRYSLER', 'JETTA', 'TSURU', 'AVEO']):
                    dept_final = 'Automotriz'
                elif any(p in d_u for p in ['PUNTO', 'SEGURIDAD']):
                    dept_final = 'Seguridad / Punto'
                else:
                    dept_final = 'Residencial'
            else:
                dept_final = depto_orig if depto_orig and depto_orig != '- Sin Departamento -' else 'General'

        # Limpiar la descripción: quitar la etiqueta de gaveta (AUxx), espacios múltiples y basura
        desc_clean = regex_loc_paren.sub('', desc_raw)
        desc_clean = re.sub(r'\s+', ' ', desc_clean).strip()

        # Construir nombre limpio para catálogo
        # Si la descripción empieza con el código, quitamos el código repetido al inicio si ya es redundante
        nombre_clean = desc_clean
        if nombre_clean.upper().startswith(cod_raw.upper() + ' '):
            nombre_clean = nombre_clean[len(cod_raw):].strip()
        if not nombre_clean:
            nombre_clean = cod_raw

        ubicaciones_finales.append(loc_final)
        deptos_finales.append(dept_final)
        descripciones_limpias.append(desc_clean)
        nombres_finales.append(nombre_clean)

    print(f"  [OK] Ubicaciones asignadas/actualizadas prioritariamente desde PDFs: {updated_from_pdf_count}")
    print(f"  [OK] Ubicaciones recuperadas de descripciones antiguas: {extracted_from_desc_count}")
    print(f"  [OK] Total de productos con ubicación física definida: {sum(1 for u in ubicaciones_finales if u)}")

    # -------------------------------------------------------------------------
    # 4. DETECCIÓN DE MARCAS, LÍNEAS ECONÓMICAS Y UNIFICACIÓN DE MOLDES
    # -------------------------------------------------------------------------
    print("\n[4/5] Clasificando marcas, versiones económicas y unificando moldes cerrajeros...")

    marcas_finales = []
    marcas_conocidas = [
        'JMA', 'Alba', 'Phillips', 'Ilco', 'Silca', 'Dexter', 'Austral', 'Yale', 
        'Tesa', 'Kwikset', 'Schlage', 'Lock', 'Assa', 'Corbin', 'Truper', 'Fulgore',
        'KEYDIY', 'Xhorse', 'Lishi', 'CARprog', 'Italika', 'Yamaha', 'Honda', 'Bajaj',
        'Ford', 'Chevrolet', 'Nissan', 'Volkswagen', 'Chrysler', 'Toyota'
    ]

    for idx, row in df.iterrows():
        cod = row['codigo_raw']
        desc = descripciones_limpias[idx]
        combined = f"{cod} {desc}".upper()

        # Regla de Terminación E (Línea Económica: Dexter, Austral, Yale)
        # Comprobar si el código termina en E (ej. R52E, R52LE, PHI-14DE, PHI-5DE, Y152E, X176E)
        is_economic_key = False
        cod_clean_upper = cod.upper()
        # Verificar si termina en E y antes hay números o clave de llave
        if re.search(r'[0-9][A-Z]*E$', cod_clean_upper) or re.search(r'-(?:14DE|5DE)$', cod_clean_upper):
            is_economic_key = True

        detected_marca = None
        if is_economic_key:
            if 'DEXTER' in combined or 'DEX-' in combined or '(DEX' in combined:
                detected_marca = 'Dexter'
            elif 'AUSTRAL' in combined or 'AUS-' in combined:
                detected_marca = 'Austral'
            elif 'YALE' in combined or 'YA-' in combined:
                detected_marca = 'Yale'
            else:
                detected_marca = 'Económica (Dexter/Austral/Yale)'
        else:
            # Buscar en lista de marcas conocidas
            for m in marcas_conocidas:
                # Coincidencia con límites de palabra para evitar falsos positivos
                if re.search(r'\b' + re.escape(m.upper()) + r'\b', combined):
                    detected_marca = m
                    break

        if not detected_marca:
            if 'JMA/ALBA' in combined or 'ALBA' in combined:
                detected_marca = 'Alba'
            elif 'JMA' in combined:
                detected_marca = 'JMA'
            else:
                detected_marca = 'Genérica'

        marcas_finales.append(detected_marca)

    # UNIFICACIÓN DE MOLDES (codigo_equivalencia)
    # Grafo de equivalencias cerrajeras mediante Disjoint-Set (Union-Find)
    uf_parent = {}
    canonical_repr = {} # root -> clave_canonica_bonita

    def uf_find(i):
        if uf_parent.setdefault(i, i) != i:
            uf_parent[i] = uf_find(uf_parent[i])
        return uf_parent[i]

    def uf_union(i, j):
        root_i = uf_find(i)
        root_j = uf_find(j)
        if root_i != root_j:
            uf_parent[root_i] = root_j

    # REGLAS MAESTRAS DE EQUIVALENCIA OBLIGATORIAS (Cerrajería México)
    # Regla de Oro: PHI-52 (JMA), R-52 (Alba), R52E (Dexter/Económica), DEX-52, 52 -> Molde raíz R52
    moldes_maestros = {
        'R52': ['R52', 'R-52', 'PHI-52', 'PHI52', 'DEX-52', 'DEX52', '52', 'R52E', 'R52-AL', 'R52-DECORADA', 'R52D', 'R52G', 'R52P'],
        'R52L': ['R52L', 'R-52L', 'PHI-52L', 'PHI52L', 'DEX-52L', 'DEX52L', '52L', 'R52LE', 'PH52L', 'R52LD', 'R52LP'],
        'R58': ['R58', 'R-58', 'PHI-58', '58', 'R58E', 'R58L', 'LOC-5D', 'RE73'],
        'R9': ['R9', 'R-9', 'PHI-9', '9', 'R9E', 'R9L', 'YA-17I'],
        'R77': ['R77', 'R-77', 'R77C', 'AUS-6D', 'RE47'],
        'R1': ['R1', 'R-1', 'R1E', 'R1D', 'R1P', 'R1-DECORADA'],
        'R2': ['R2', 'R-2', 'R2E', 'R2D'],
        'R20': ['R20', 'R20A', 'R20C', 'R20L', 'R20N'],
        'R26': ['R26', 'R-26', 'R26E'],
        'R47': ['R47', 'R47L', 'R47N'],
        'R76': ['R76', 'PHI-4D'],
        'PHI-14D': ['PHI-14D', 'PHI14D', 'PHI-14DE', 'PHI14DE', 'AS200', 'PH-200', 'PH3LR', 'PHL3R'],
        'PHI-5D': ['PHI-5D', 'PHI5D', 'PHI-5DE', 'PHI5DE', 'AS400', '6329'],
        'A74': ['A74', 'A74L', 'A74LC'],
        'A79C': ['A79C', 'DAT-17S', 'TSURU'],
        'A81': ['A81', 'A81A', 'A81AP', 'A81D', 'A81DP', 'A81E', 'A81EP', 'CHR-14S', 'CHR-15', 'Y157P', 'Y159', 'CR7'],
        'A86': ['A86', 'A86C', 'A86CP', 'A86P', 'OP-SE', 'OP-DS', 'OP-S-PS', 'OP-7P'],
        'A88': ['A88', 'A88C', 'A88-TRANS'],
        'A89': ['A89', 'A89P', 'A89S', 'A89SP', 'GM-14', 'GM-14P'],
        'A91': ['A91', 'A91P', 'DA-34', 'DAT-16', 'DN9'],
        'F2': ['F2A', 'F2B', 'F2E', 'F2H', 'F2HP', 'F2K', 'F2LL', 'FO-8D', 'FO-21DS', 'FO15DS', 'FO15DPS', 'FO-11DS', 'FO27DS'],
        'BAJ-4AP': ['BAJ-4AP', 'SLG3S', 'PU2P', 'PULSAR'],
        'HOND-48': ['HOND-48', 'HOND-48P', 'HOND-48DP', 'HOND-48CP'],
        'ITA-1P': ['ITA-1P', 'IT-1P', 'ITA-1DP'],
        'SUZU-12': ['SUZU-12', 'SUZU-12P', 'SUZU-12D', 'SUZU-12DP'],
        'YAMA-26': ['YAMA-26', 'YAMA-26P', 'YAMA-26D', 'YAMA-26DP'],
        'BKY-1': ['BKY-1', 'X24'],
        'BKY-2': ['BKY-2', 'X24S', 'PH725'],
        'AMG-10D': ['AMG-10D', 'SE93'],
        'AMG-8D': ['AMG-8D', 'SE113'],
        'AS800': ['AS800', 'PHI-13'],
        'CMX-10D': ['CMX-10D', 'ED42DN']
    }

    # Inicializar reglas maestras en Union-Find
    for canon_name, aliases in moldes_maestros.items():
        c_root_key = clean_key_token(canon_name)
        canonical_repr[c_root_key] = canon_name
        for al in aliases:
            al_key = clean_key_token(al)
            uf_union(c_root_key, al_key)

    # Alimentar el grafo con las descripciones del inventario
    for idx, row in df.iterrows():
        cod = row['codigo_raw']
        desc = row['descripcion_raw']
        cod_base = re.sub(r'\s+DUP$', '', cod, flags=re.I).strip()
        c_clean = clean_key_token(cod_base)

        # Buscar paréntesis con claves equivalentes
        parens = re.findall(r'\(([^)]+)\)', desc)
        for p_str in parens:
            p_str = p_str.strip()
            # Ignorar ubicaciones (AUxx, RExx, etc.)
            if re.match(r'^(?:AU|RE|SE|MO|Mt)\s*\d+', p_str, re.I):
                continue
            # Ignorar palabras genéricas
            if p_str.upper() in ['LARGA', 'CORTA', 'DUPLICADO', 'VARIOS', 'PLUS', 'UNIVERSAL']:
                continue
            p_clean = clean_key_token(p_str)
            if len(p_clean) >= 2 and len(p_clean) <= 12:
                uf_union(c_clean, p_clean)

    # Alimentar el grafo desde las etiquetas de los PDFs SOLO si son variantes explícitas con '|' (ej. F2E|FO-8D)
    for _, content, _ in pdf_labels:
        if '|' in content:
            parts = [clean_key_token(x) for x in content.split('|') if len(clean_key_token(x)) >= 3]
            if len(parts) >= 2:
                for idx_p in range(1, len(parts)):
                    uf_union(parts[0], parts[idx_p])

    # Determinar el nombre representativo óptimo para cada cluster de Union-Find
    # Regla: Nombre más común y corto, priorizando R... canónico
    cluster_members = defaultdict(list)
    for k in list(uf_parent.keys()):
        root = uf_find(k)
        cluster_members[root].append(k)

    cluster_to_canon = {}
    for root, members in cluster_members.items():
        # 1. Si ya tiene canonical_repr asignado por reglas maestras
        if root in canonical_repr:
            cluster_to_canon[root] = canonical_repr[root]
            continue
        # 2. Buscar si algún miembro tiene canonical_repr
        found_canon = None
        for m in members:
            if m in canonical_repr:
                found_canon = canonical_repr[m]
                break
        if found_canon:
            cluster_to_canon[root] = found_canon
            continue
        # 3. Buscar el miembro que empiece con R + dígitos (Alba residencial común)
        r_members = [m for m in members if re.match(r'^R\d+[A-Z]*$', m)]
        if r_members:
            r_members.sort(key=lambda x: (len(x), x))
            cluster_to_canon[root] = r_members[0]
            continue
        # 4. Buscar el miembro más corto sin sufijo E económico
        cleaned_members = []
        for m in members:
            clean_m = re.sub(r'E$', '', m) if len(m) > 3 and m.endswith('E') else m
            cleaned_members.append(clean_m)
        cleaned_members.sort(key=lambda x: (len(x), x))
        cluster_to_canon[root] = cleaned_members[0]

    # Asignar codigo_equivalencia a cada fila del catálogo
    moldes_finales = []
    for idx, row in df.iterrows():
        cod = row['codigo_raw']
        cod_base = re.sub(r'\s+DUP$', '', cod, flags=re.I).strip()
        c_clean = clean_key_token(cod_base)

        # Regla de normalización cerrajera:
        # Si la clave termina en E, o tiene prefijos PHI/DEX/AUS, buscar el molde raíz
        molde_asignado = None
        if c_clean in uf_parent:
            root = uf_find(c_clean)
            molde_asignado = cluster_to_canon.get(root)

        if not molde_asignado:
            # Si el código termina en E (económica), su molde es la versión sin E
            if len(c_clean) >= 3 and c_clean.endswith('E'):
                base_sin_e = c_clean[:-1]
                if base_sin_e in uf_parent:
                    root = uf_find(base_sin_e)
                    molde_asignado = cluster_to_canon.get(root, base_sin_e)
                else:
                    molde_asignado = base_sin_e
            # Si empieza con DEX- o PHI-, el molde es la versión normalizada
            elif c_clean.startswith('DEX') and len(c_clean) > 3:
                num = c_clean[3:]
                molde_candidato = f"R{num}" if num.isdigit() else num
                molde_asignado = molde_candidato
            elif c_clean.startswith('PHI') and len(c_clean) > 3:
                num = c_clean[3:]
                molde_candidato = f"R{num}" if num.isdigit() else f"PHI-{num}"
                molde_asignado = molde_candidato
            elif re.match(r'^R\d+', c_clean):
                # Extraer la raíz Rxx (ej. R52-AL -> R52)
                m = re.match(r'^(R\d+)', c_clean)
                molde_asignado = m.group(1) if m else c_clean

        # Si no es llave/forja ni pertenece a un grupo de molde conocido, dejar None
        depto_row = deptos_finales[idx]
        if not molde_asignado and depto_row in ['Residencial', 'Automotriz', 'Motos', 'Seguridad / Punto']:
            if len(c_clean) >= 2 and len(c_clean) <= 8 and not c_clean.isdigit():
                molde_asignado = c_clean

        moldes_finales.append(molde_asignado)

    print(f"  [OK] Total de productos con Molde (codigo_equivalencia) asignado: {sum(1 for m in moldes_finales if m)}")
    unique_molds = set(m for m in moldes_finales if m)
    print(f"  [OK] Grupos únicos de moldes universales creados: {len(unique_molds)}")

    # -------------------------------------------------------------------------
    # 5. ESTRUCTURACIÓN DE PRECIOS, STOCK Y GENERACIÓN DE SALIDAS
    # -------------------------------------------------------------------------
    print("\n[5/5] Estructurando dataset final y generando CSV, Excel y Reporte...")

    def parse_money(val):
        if pd.isna(val): return 0.0
        s = str(val).replace('$', '').replace(',', '').strip()
        try:
            return round(float(s), 2)
        except Exception:
            return 0.0

    def parse_float(val, default=0.0):
        if pd.isna(val): return default
        try:
            return float(val)
        except Exception:
            return default

    codigos_out = []
    skus_out = []
    nombres_out = []
    descripciones_out = []
    marcas_out = []
    moldes_out = []
    ubicaciones_out = []
    deptos_out = []
    precios_compra_out = []
    precios_venta_out = []
    precios_cerrajero_out = []
    precios_taller_out = []
    precios_mayoreo_out = []
    cantidades_mayoreo_out = []
    stocks_actuales_out = []
    stocks_minimos_out = []
    es_a_granel_out = []
    es_servicio_out = []

    for idx, row in df.iterrows():
        cod = row['codigo_raw']
        desc = descripciones_limpias[idx]
        nombre = nombres_finales[idx]
        marca = marcas_finales[idx]
        molde = moldes_finales[idx]
        ubicacion = ubicaciones_finales[idx]
        depto = deptos_finales[idx]

        p_compra = parse_money(row.get('costo_raw', 0.0))
        p_venta = parse_money(row.get('venta_raw', 0.0))
        p_mayoreo_raw = parse_money(row.get('mayoreo_raw', 0.0))

        stock_act = parse_float(row.get('stock_raw', 0.0))
        stock_min = parse_float(row.get('inv_minimo_raw', 5.0))
        if stock_min <= 0:
            stock_min = 5.0 if depto in ['Residencial', 'Automotriz', 'Motos', 'Seguridad / Punto'] else 1.0

        # Regla de detección de servicio
        es_serv = 0
        if depto == 'Servicios' or 'DUP' in cod.upper() or 'SERVICIO' in desc.upper() or 'CAMBIO CARCAZA' in desc.upper():
            es_serv = 1

        # Precios escalonados cerrajeros
        p_mayoreo = None
        cant_mayoreo = None
        if p_mayoreo_raw > 0 and p_mayoreo_raw < p_venta:
            p_mayoreo = p_mayoreo_raw
            cant_mayoreo = 5.0

        # Precio Cerrajero (Colega Gremial)
        if p_mayoreo is not None:
            p_cerrajero = p_mayoreo
        elif p_venta > 0:
            # Tarifa colega con aprox 25% de descuento sobre precio casual, cubriendo compra
            descuento = round(p_venta * 0.75, 2)
            p_cerrajero = max(descuento, p_compra * 1.15) if p_compra > 0 else descuento
            p_cerrajero = round(p_cerrajero, 2)
        else:
            p_cerrajero = None

        # Precio Taller (Automotriz / Especial)
        if p_venta > 0:
            desc_taller = round(p_venta * 0.85, 2)
            p_taller = max(desc_taller, p_compra * 1.25) if p_compra > 0 else desc_taller
            p_taller = round(p_taller, 2)
        else:
            p_taller = None

        granel = 1 if (stock_act % 1 != 0) else 0

        codigos_out.append(cod)
        skus_out.append(cod)
        nombres_out.append(nombre)
        descripciones_out.append(desc)
        marcas_out.append(marca)
        moldes_out.append(molde if molde else '')
        ubicaciones_out.append(ubicacion if ubicacion else '')
        deptos_out.append(depto)
        precios_compra_out.append(p_compra)
        precios_venta_out.append(p_venta)
        precios_cerrajero_out.append(p_cerrajero if p_cerrajero is not None else '')
        precios_taller_out.append(p_taller if p_taller is not None else '')
        precios_mayoreo_out.append(p_mayoreo if p_mayoreo is not None else '')
        cantidades_mayoreo_out.append(cant_mayoreo if cant_mayoreo is not None else '')
        stocks_actuales_out.append(stock_act)
        stocks_minimos_out.append(stock_min)
        es_a_granel_out.append(granel)
        es_servicio_out.append(es_serv)

    df_final = pd.DataFrame({
        'codigo': codigos_out,
        'sku': skus_out,
        'nombre': nombres_out,
        'descripcion': descripciones_out,
        'marca': marcas_out,
        'codigo_equivalencia': moldes_out,
        'ubicacion': ubicaciones_out,
        'departamento': deptos_out,
        'precio_compra': precios_compra_out,
        'precio_venta': precios_venta_out,
        'precio_cerrajero': precios_cerrajero_out,
        'precio_taller': precios_taller_out,
        'precio_mayoreo': precios_mayoreo_out,
        'cantidad_mayoreo': cantidades_mayoreo_out,
        'stock_actual': stocks_actuales_out,
        'stock_minimo': stocks_minimos_out,
        'es_a_granel': es_a_granel_out,
        'es_servicio': es_servicio_out,
    })

    # Guardar CSV UTF-8
    csv_out_path = os.path.join(migracion_dir, "catalogo_migrado_pos.csv")
    df_final.to_csv(csv_out_path, index=False, encoding='utf-8')
    print(f"  [OK] Archivo CSV generado con éxito: {csv_out_path}")

    # Guardar Excel para inspección
    xlsx_out_path = os.path.join(migracion_dir, "catalogo_migrado_revision.xlsx")
    df_final.to_excel(xlsx_out_path, index=False)
    print(f"  [OK] Archivo Excel generado con éxito: {xlsx_out_path}")

    # Generar Reporte Markdown
    report_path = os.path.join(migracion_dir, "reporte_migracion.md")
    report_content = f"""# Reporte de Migración Inteligente y Limpieza de Catálogo POS

**Fecha de Ejecución:** {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}  
**Archivos Fuente Procesados:**
- `inventario_eleventa.xls` (Inventario histórico de Eleventa/CARprog)
- `Etiquetas1.pdf` (Posiciones y gavetas recién etiquetadas físicamente)
- `Etiquetas2.pdf` (Matriz digitalizada de gavetas y coordenadas)

---

## 1. Métricas Generales del Proceso ETL
- **Total de productos leídos desde Eleventa:** {len(df_raw)}
- **Método de lectura aplicado:** `{read_method}`
- **Total de productos exportados al nuevo POS:** {len(df_final)}
- **Ubicaciones actualizadas prioritariamente desde PDFs:** {updated_from_pdf_count}
- **Ubicaciones recuperadas desde descripciones históricas:** {extracted_from_desc_count}
- **Total de productos con ubicación física asignada:** {sum(1 for u in ubicaciones_out if u)}
- **Productos clasificados como Servicios (`es_servicio = 1`):** {sum(1 for s in es_servicio_out if s == 1)}
- **Productos físicos con control de inventario (`es_servicio = 0`):** {sum(1 for s in es_servicio_out if s == 0)}

---

## 2. Unificación de Moldes Cerrajeros (`codigo_equivalencia`)
- **Total de productos con Molde Raíz asignado:** {sum(1 for m in moldes_out if m)}
- **Total de Grupos Únicos de Moldes Creados:** {len(unique_molds)}
- **Ejemplo Maestro R52:**
  - Todas las variantes (`PHI-52`, `R-52`, `R52E`, `DEX-52`, `52`, `R52-AL`, `R52-DECORADA`, `R52D`, `R52G`, `R52P`) comparten de forma unificada: **`codigo_equivalencia = 'R52'`**.
- **Ejemplo Maestro R52L:**
  - Todas las variantes (`PHI-52L`, `R52L`, `R52LE`, `DEX-52L`, `R52LD`, `R52LP`) comparten: **`codigo_equivalencia = 'R52L'`**.
- **Ejemplos Phillips Puntos:**
  - Familia `PHI-14D`, `PHI-14DE`, `AS200` comparten: **`codigo_equivalencia = 'PHI-14D'`**.
  - Familia `PHI-5D`, `PHI-5DE`, `AS400`, `6329` comparten: **`codigo_equivalencia = 'PHI-5D'`**.

---

## 3. Distribución por Departamentos
{df_final['departamento'].value_counts().to_markdown()}

---

## 4. Distribución por Marcas Detectadas
{df_final['marca'].value_counts().head(20).to_markdown()}

---

## 5. Muestra de Registros Migrados
{df_final[['codigo', 'nombre', 'marca', 'codigo_equivalencia', 'ubicacion', 'departamento', 'precio_venta', 'stock_actual']].head(15).to_markdown()}

---
*Reporte generado automáticamente por `scripts/etl_migracion.py`.*
"""
    with open(report_path, "w", encoding="utf-8") as rf:
        rf.write(report_content)
    print(f"  [OK] Reporte Markdown generado con éxito: {report_path}")

    print("\n" + "=" * 80)
    print("      PROCESO ETL FINALIZADO CON ÉXITO")
    print("=" * 80)

if __name__ == "__main__":
    main()
