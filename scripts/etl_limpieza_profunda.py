#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
FASE 2: LIMPIEZA Y CONSOLIDACIÓN PROFUNDA DE DATOS (ETL POS CERRAJERÍA)
-----------------------------------------------------------------------
1. Consolida los departamentos fragmentados en 9 categorías maestras limpias.
2. Re-verifica ubicaciones prioritarias desde Etiquetas1.pdf y Etiquetas2.pdf
   (corrigiendo falsos positivos numéricos en adaptadores/memorias).
3. Detecta, fusiona y deduplica productos físicos repetidos (conservando ubicación
   más reciente en gaveta, molde común, precios escalonados y sumando stock y
   métricas históricas de ventas).
4. Reemplaza la proliferación de servicios individuales por el nuevo modelo de
   Servicios Maestros Configurables por Departamento (Dynamic Runtime BOM).
5. Sincroniza:
   - C:\POS\migracion\catalogo_migrado_pos.csv
   - C:\POS\client\assets\catalogo_migrado_pos.csv
   - C:\POS\backend\data\storage.json
   - PostgreSQL en Docker (pos-postgres), si el daemon está activo.
"""

import csv
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

MIGRACION_DIR = r"C:\POS\migracion"
CSV_PATH = os.path.join(MIGRACION_DIR, "catalogo_migrado_pos.csv")
RAW_BACKUP_PATH = os.path.join(MIGRACION_DIR, "catalogo_migrado_pos.raw_backup.csv")
ASSETS_CSV_PATH = r"C:\POS\client\assets\catalogo_migrado_pos.csv"
STORAGE_JSON_PATH = r"C:\POS\backend\data\storage.json"
PDF1_PATH = os.path.join(MIGRACION_DIR, "Etiquetas1.pdf")
PDF2_PATH = os.path.join(MIGRACION_DIR, "Etiquetas2.pdf")

VALID_DEPARTMENTS = {
    "Residencial",
    "Automotriz",
    "Seguridad / Punto",
    "Motos",
    "Pilas y Baterías",
    "Transponders y Chips",
    "Controles y Carcasas",
    "Cerraduras y Candados",
    "Herramientas y Accesorios",
    "Servicios",
}

# Servicios Maestros Configurables por Departamento (Dynamic Runtime BOM)
MASTER_SERVICES = [
    {
        "codigo": "SRV-CAM-PILA",
        "sku": "SRV-CAM-PILA",
        "nombre": "Cambio / Instalación de Pila en Control",
        "descripcion": "Instalación profesional de batería de litio, verificación de voltaje y prueba de emisión RF",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Pilas y Baterías,Controles y Carcasas",
        "precio_compra": 0.0,
        "precio_venta": 80.0,
        "precio_cerrajero": 50.0,
        "precio_taller": 60.0,
        "precio_mayoreo": 60.0,
        "cantidad_mayoreo": 5.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-CAM-CAR",
        "sku": "SRV-CAM-CAR",
        "nombre": "Cambio de Carcasa / Adaptación",
        "descripcion": "Sustitución de carcasa automotriz, trasplante de tableta electrónica y adaptación de espadín",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Controles y Carcasas",
        "precio_compra": 0.0,
        "precio_venta": 250.0,
        "precio_cerrajero": 150.0,
        "precio_taller": 200.0,
        "precio_mayoreo": 180.0,
        "cantidad_mayoreo": 3.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-REP-CTRL",
        "sku": "SRV-REP-CTRL",
        "nombre": "Reparación de Control / Soldadura de Microswitch / Botón",
        "descripcion": "Reparación electrónica de circuito impreso de control remoto, microswitches y soldadura SMD",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Controles y Carcasas",
        "precio_compra": 0.0,
        "precio_venta": 50.0,
        "precio_cerrajero": 30.0,
        "precio_taller": 35.0,
        "precio_mayoreo": 35.0,
        "cantidad_mayoreo": 5.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-PROG-CTRL",
        "sku": "SRV-PROG-CTRL",
        "nombre": "Programación de Control / Telemando",
        "descripcion": "Generación y programación inalámbrica de control remoto telemando o llave de proximidad",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Controles y Carcasas,Automotriz",
        "precio_compra": 0.0,
        "precio_venta": 500.0,
        "precio_cerrajero": 350.0,
        "precio_taller": 400.0,
        "precio_mayoreo": 400.0,
        "cantidad_mayoreo": 2.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-PROG-CHIP",
        "sku": "SRV-PROG-CHIP",
        "nombre": "Programación de Transponder / Chip",
        "descripcion": "Programación por OBDII o clonación de chip transponder inmovilizador automotriz",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Transponders y Chips,Automotriz",
        "precio_compra": 0.0,
        "precio_venta": 500.0,
        "precio_cerrajero": 350.0,
        "precio_taller": 400.0,
        "precio_mayoreo": 400.0,
        "cantidad_mayoreo": 2.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-DUP-RES",
        "sku": "SRV-DUP-RES",
        "nombre": "Duplicado de Llave Residencial / Tradicional",
        "descripcion": "Servicio de corte y duplicado para llave residencial tradicional, chapa doméstica o candado",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Residencial",
        "precio_compra": 0.0,
        "precio_venta": 20.0,
        "precio_cerrajero": 15.0,
        "precio_taller": 17.0,
        "precio_mayoreo": 16.0,
        "cantidad_mayoreo": 5.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-DUP-SEG",
        "sku": "SRV-DUP-SEG",
        "nombre": "Duplicado de Llave de Seguridad / Punto",
        "descripcion": "Servicio de corte de llave multipunto, alta seguridad, tetra o tubular",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Seguridad / Punto",
        "precio_compra": 0.0,
        "precio_venta": 60.0,
        "precio_cerrajero": 45.0,
        "precio_taller": 50.0,
        "precio_mayoreo": 50.0,
        "cantidad_mayoreo": 5.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-DUP-AUT",
        "sku": "SRV-DUP-AUT",
        "nombre": "Duplicado / Corte de Llave Automotriz",
        "descripcion": "Servicio de corte mecánico o regata láser para llave automotriz hueca o con forja",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Automotriz",
        "precio_compra": 0.0,
        "precio_venta": 50.0,
        "precio_cerrajero": 30.0,
        "precio_taller": 35.0,
        "precio_mayoreo": 35.0,
        "cantidad_mayoreo": 3.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-DUP-MOT",
        "sku": "SRV-DUP-MOT",
        "nombre": "Duplicado de Llave para Moto",
        "descripcion": "Servicio de corte y duplicado de llave para motocicleta o motoneta",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Motos",
        "precio_compra": 0.0,
        "precio_venta": 35.0,
        "precio_cerrajero": 20.0,
        "precio_taller": 25.0,
        "precio_mayoreo": 25.0,
        "cantidad_mayoreo": 3.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-GEN-CERO",
        "sku": "SRV-GEN-CERO",
        "nombre": "Generación de Llave desde Cero",
        "descripcion": "Elaboración, lectura de combinación, corte y programación por pérdida total",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Automotriz,Cerraduras y Candados,Motos",
        "precio_compra": 0.0,
        "precio_venta": 1200.0,
        "precio_cerrajero": 800.0,
        "precio_taller": 1000.0,
        "precio_mayoreo": 900.0,
        "cantidad_mayoreo": 2.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
    {
        "codigo": "SRV-APER-COMB",
        "sku": "SRV-APER-COMB",
        "nombre": "Servicio de Apertura / Cambio de Combinación / Reparación de Cerradura",
        "descripcion": "Apertura técnica, cambio o igualación de combinación y reparación de cerrajería en taller o campo",
        "marca": "Taller",
        "codigo_equivalencia": "",
        "ubicacion": "",
        "departamento": "Servicios",
        "departamentos_aplicables": "Cerraduras y Candados,Residencial,Automotriz,Seguridad / Punto",
        "precio_compra": 0.0,
        "precio_venta": 250.0,
        "precio_cerrajero": 180.0,
        "precio_taller": 200.0,
        "precio_mayoreo": 200.0,
        "cantidad_mayoreo": 3.0,
        "stock_actual": 999.0,
        "stock_minimo": 0.0,
        "es_a_granel": 0,
        "es_servicio": 1,
        "ventas_ultimos_30dias": 0.0,
        "total_unidades_vendidas": 0.0,
        "ultima_venta_at": "",
    },
]


def clean_token(val: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", str(val or "").upper())


def format_location_code(loc_str: str) -> str:
    if not loc_str:
        return ""
    m = re.match(r"^(AU|RE|SE|MO|MT)\s*-?\s*(\d+[\w/-]*)$", loc_str.strip(), re.I)
    if m:
        prefix = m.group(1).upper()
        if prefix == "MT":
            prefix = "MO"
        num_part = m.group(2).strip().upper()
        return f"{prefix}-{num_part}"
    return loc_str.strip().upper()


def dept_from_location(loc_norm: str) -> str:
    if not loc_norm:
        return ""
    if loc_norm.startswith("AU-"):
        return "Automotriz"
    if loc_norm.startswith("RE-"):
        return "Residencial"
    if loc_norm.startswith("SE-"):
        return "Seguridad / Punto"
    if loc_norm.startswith("MO-"):
        return "Motos"
    return ""


def load_pdf_locations() -> dict:
    """Extrae ubicaciones de Etiquetas1.pdf y Etiquetas2.pdf con prioridad a Etiquetas2.pdf."""
    pdf_map = {}
    try:
        import pdfplumber
    except ImportError:
        return pdf_map

    labels = []
    if os.path.exists(PDF1_PATH):
        with pdfplumber.open(PDF1_PATH) as p1:
            for page in p1.pages:
                text = page.extract_text() or ""
                matches = list(re.finditer(r"\(((?:AU|RE|SE|MO|Mt)\s*\d+[\w/-]*)\)", text, re.I))
                for i, m in enumerate(matches):
                    loc_raw = m.group(1).strip()
                    start = m.end()
                    end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
                    content = re.sub(r"\s+", " ", text[start:end].strip())
                    if content and "[uncataloged]" not in content.lower():
                        labels.append((loc_raw, content, "Etiquetas1.pdf"))

    if os.path.exists(PDF2_PATH):
        with pdfplumber.open(PDF2_PATH) as p2:
            for page in p2.pages:
                for tbl in (page.extract_tables() or []):
                    for row in tbl:
                        for cell in row:
                            if not cell:
                                continue
                            m = re.search(r"\(((?:AU|RE|SE|MO|Mt)\s*\d+[\w/-]*)\)\s*(.*)", str(cell).strip(), re.I | re.S)
                            if m:
                                loc_raw = m.group(1).strip()
                                content = re.sub(r"\s+", " ", m.group(2).strip())
                                if content and "[uncataloged]" not in content.lower():
                                    labels.append((loc_raw, content, "Etiquetas2.pdf"))

    for loc_raw, content, src in labels:
        loc_norm = format_location_code(loc_raw)
        subtokens = []
        if "|" in content:
            subtokens.extend([x.strip() for x in content.split("|")])
        elif "/" in content:
            parts = [x.strip() for x in content.split("/")]
            base = parts[0]
            subtokens.append(base)
            for p in parts[1:]:
                if len(p) <= 2 and p.isalpha():
                    subtokens.append(base + p)
                else:
                    subtokens.append(p)
        else:
            words = content.split()
            if words:
                subtokens.append(words[0])
                if len(words) > 1 and len(words[1]) >= 3 and words[1].lower() not in {"p", "pulsar", "aveo", "spark"}:
                    subtokens.append(words[1])
            subtokens.append(content)

        for st in subtokens:
            tok = clean_token(st)
            if tok and len(tok) >= 2 and not tok.isdigit():
                pdf_map[tok] = (loc_norm, src)

    return pdf_map


def parse_float(val, default=0.0) -> float:
    if val is None:
        return default
    s = str(val).replace("$", "").replace(",", "").strip()
    if not s:
        return default
    try:
        return float(s)
    except ValueError:
        return default


def parse_opt_float(val):
    if val is None:
        return None
    s = str(val).replace("$", "").replace(",", "").strip()
    if not s:
        return None
    try:
        v = float(s)
        return v if v > 0 else None
    except ValueError:
        return None


def is_legacy_service_row(row: dict) -> bool:
    """Identifica todos los servicios individuales antiguos que deben reemplazarse por Servicios Maestros."""
    cod = row.get("codigo", "").strip().upper()
    nom = row.get("nombre", "").strip().upper()
    desc = row.get("descripcion", "").strip().upper()
    depto = row.get("departamento", "").strip().upper()
    es_srv = str(row.get("es_servicio", "0")).strip() == "1"

    # Si ya es uno de los nuevos Servicios Maestros, tratarlo como servicio reemplazable por la lista maestra fresca
    if cod.startswith("SRV-"):
        return True

    # Rescatar productos físicos reales mal clasificados como servicio en Eleventa
    RESCUED_PHYSICAL_CODES = {"BANDA-MG", "MEC-TRANSIT", "VARILLA"}
    if cod in RESCUED_PHYSICAL_CODES:
        return False

    if es_srv or depto == "SERVICIOS":
        return True

    # Servicios sueltos que quedaron con es_servicio=0 o códigos particulares en el CSV previo
    EXPLICIT_LEGACY_SERVICES = {
        "AP-AUTO",
        "DA",
        "LC",
        "PROG7",
        "SER5",
        "SER6",
        "SER7",
        "CORTE-AUTO",
        "CORTE-MOTO",
        "CORTE",
        "CORTE ABLOY",
        "CORTE PUNTOS",
        "CORTE REGATA",
        "CORTE TIBBE",
        "CORTE-TUBULAR",
        "DIAG",
        "REP-CAJUELA",
        "REV-ECU",
        "REV1",
        "REV2",
        "REV3",
        "REV4",
        "REP-CODO",
        "RA08-SER",
        "AKM",
        "PIN CODE",
        "CR-2016-1",
        "CR-2016-2",
        "CR-2025 SER",
        "CR-2032 SER",
        "CR-1620 SERVICIO",
        "CR-2032 TALLER",
        "BTN-REP",
        "CONTROL-REP",
        "CONTROL-REP2",
        "CONTROL-REP3",
        "CONTROL-REP4",
        "CZ-OP SER",
        "CZ-OP3B SER",
        "CC-SPARK",
        "CC-ASTRA3B SER",
    }
    if cod in EXPLICIT_LEGACY_SERVICES:
        return True

    if re.search(r"(?:\bDUP$|-SER$|^PROG\d+$|^SER\d+$|^CER\d+$|^REP\d+$)", cod):
        return True

    combined = f"{nom} {desc}"
    if any(
        kw in combined
        for kw in [
            "SERVICIO APERTURA",
            "APERTURA AUTOMOTRIZ",
            "APERTURA DE CERRADURA",
            "APERTURA AUTO",
            "LECTURA CORTE",
            "DUPLICADO AUTOMOTRIZ CON TRANSPONDER",
            "CAMBIO CARCASA",
            "CAMBIO CARCAZA",
            "ESCANEO VEHICULO",
            "REVISION COMPUTADORA",
            "DIAGNOSTICO AUTOMOTRIZ",
        ]
    ):
        return True

    return False


def is_bogus_pdf_location(cod: str, nom: str, desc: str, orig_depto: str) -> bool:
    """Detecta ítems electrónicos/herramientas con códigos cortos ('3','6','8','11','22-A') que recibieron gaveta falsa."""
    combined = f"{nom} {desc} {orig_depto}".upper()
    non_key_terms = [
        "ADAPTADOR",
        "UPA",
        "SOIC",
        "EEPROM",
        "MEMORIA",
        "PROGRAMADOR",
        "PINZA",
        "SOCKET",
        "EMULADOR",
        "INTERFAZ",
        "INTERFACE",
        "OBD",
        "PUNTA LOGICA",
        "PUNTA LÓGICA",
        "FRECUENCIOMETRO",
        "MULTIMETRO",
        "SOLDADURA",
        "FLUX",
        "CAUTIN",
        "MICROSCOPIO",
    ]
    if any(t in combined for t in non_key_terms):
        return True
    if cod.isdigit() and len(cod) <= 3:
        return True
    return False


def classify_physical_department(cod: str, nom: str, desc: str, ubicacion: str, orig_depto: str) -> str:
    """Clasifica cada producto físico en uno de los 8 departamentos físicos estandarizados."""
    c_up = cod.upper().strip()
    d_up = f"{nom} {desc}".upper()
    o_up = orig_depto.upper().strip()
    full = f"{c_up} {d_up} {o_up}"

    # 1. Transponders y Chips (Chips TP, ID48, PCF7935, Megamos, Superchip, EEPROMs inmovilizador)
    if (
        re.match(r"^(TP-|TP\d|ID48|ID46|PCF\d|8E-|XT27|SUPERCHIP|RES-V4)", c_up)
        or c_up in {"22-A", "22-S", "23", "32"}
        or o_up == "MEMORIAS"
        or any(
            kw in d_up
            for kw in [
                "TRANSPONDER",
                "MEGAMOS",
                "PCF79",
                "SUPERCHIP",
                "CHIP TP",
                "CHIP ID",
                "EEPROM",
                "MEMORIA FLASH",
                "MEMORIA POINTER",
                "95160",
                "35080",
                "93C",
                "24C",
            ]
        )
    ):
        # Excluir máquinas clonadoras o llaves huecas para transponder ("SIN CHIP" / "HUECA")
        if not any(hw in full for hw in ["MINI KEY TOOL", "KD-X2", "ZEDBULL", "MINIZEDBULL", "LLAVE HUECA", "CARCASA", "CARCAZA"]):
            return "Transponders y Chips"

    # 2. Pilas y Baterías (Pilas de botón CR-2032, CR-2016, CR-2025, CR-1616, CR-1620, CR-1220, 23A, 27A, pilas de litio)
    if (
        re.match(r"^(CR-\d{4}|CR\d{4}|CR-\d{3}|23A|27A|LR\d+|AG\d+|PILA|BATERIA)", c_up)
        or o_up in {"PILAS", "ACCESORIOS / PILAS"}
        or any(
            kw in d_up
            for kw in [
                "PILA CR",
                "PILA LITIO",
                "PILA BOTON",
                "PILA BOTÓN",
                "PILA RENATA",
                "PILA PANASONIC",
                "PILA SONY",
                "PILA MAXELL",
                "PILA ENERGIZER",
                "PILA TIANQIU",
                "BATERIA CR",
                "BATERÍA CR",
                "BATERIA PANASONIC",
                "BATERÍA PANASONIC",
                "CR-2032",
                "CR-2016",
                "CR-2025",
                "CR-1616",
                "CR-1620",
                "CR-1220",
                "CR-2450",
                "CR-1632",
            ]
        )
        or (c_up.startswith("CR-") and not any(k in d_up for k in ["CARCASA", "CARCAZA", "CONTROL"]))
    ):
        return "Pilas y Baterías"

    # 3. Controles y Carcasas (Controles remotos, carcasas, telemandos, micro-botones, alarmas)
    if (
        re.match(r"^(CC-|CZ-|KD-(?!X2)|VVDI-(?!MINI)|PR-XK|XHORSE-AZ|RA08|SA673|HU053|HK1789|HKSA1998|BTN-)", c_up)
        or any(
            kw in o_up
            for kw in [
                "ACTUADORES",
                "ALARMAS",
                "CARCAZA Y LLAVE HUECA",
                "CONTROLES VVDI",
                "CONTROLES KD",
                "CONTROLES OTROS",
                "LLAVE CON CONTROL",
                "BOTONES PARA CONTROL",
            ]
        )
        or any(
            kw in d_up
            for kw in [
                "CARCASA",
                "CARCAZA",
                "CONTROL REMOTO",
                "TELEMANDO",
                "CONTROL KEYDIY",
                "CONTROL VVDI",
                "CONTROL XHORSE",
                "CONTROL UNIVERSAL",
                "CONTROL ALARMA",
                "MICRO SWITCH",
                "MICROSWITCH",
                "BOTON CONTROL",
                "BOTÓN CONTROL",
                "ACTUADOR SEGURO",
                "ACTUADOR UNIVERSAL",
            ]
        )
    ):
        if not any(hw in full for hw in ["MINI KEY TOOL", "KD-X2", "FRECUENCIOMETRO", "PROBADOR"]):
            return "Controles y Carcasas"

    # 3. Herramientas y Accesorios (Ganzúas, Lishi, llaveros, argollas, identificadores, lubricantes, adaptadores, programadores)
    if (
        re.match(
            r"^(LISHI|LSA|SL27|SL58|GANZ|CUT-|LIMA|BL181|BANDA-MG|FLEJE|LAINA|PEINE|VARILLA|ARGO|ARILLO|IDE-|LISTON|LLAVERO|PERMATEX|ZOMS|ADP-|UPA|CARPROG|CK-?100|SBB|OBD|OPCOM|VCDS|VAG|KD-X2|AUTEL|AUTEK|XELTEC|DADO|SEG-PIN|MEC-TRANSIT)",
            c_up,
        )
        or c_up in {"G1", "G7-TUBULAR"}
        or any(
            kw in o_up
            for kw in [
                "HERRAMIENTAS",
                "PROGRAMADORES",
                "ARGOLLA METALICA",
                "LLAVEROS Y ACCESORIOS",
                "GUIAS",
                "INTERFACES",
                "SOCKET Y ADAPTADOR",
                "ADAPTADORES",
                "UPA PROGRAMADOR",
                "COMPUTADORAS Y TABLEROS",
                "PUNTA LÓGICA",
                "PUNTA LOGICA",
                "ACEITE AFLOJATODO",
                "ADAPTADOR GQ",
                "OBDII",
                "PINZAS SOIC8",
                "FRECUENCIOMETRO",
                "EMULADORES",
                "ACCESORIOS ELECTRONICA",
                "XHORSE",
                "TALLER",
            ]
        )
        or any(
            kw in d_up
            for kw in [
                "GANZUA",
                "GANZÚA",
                "LISHI",
                "LLAVERO",
                "ARGOLLA",
                "ARILLO",
                "IDENTIFICADOR",
                "AFLOJATODO",
                "LUBRICANTE",
                "GRAFITO",
                "ADAPTADOR",
                "PROGRAMADOR",
                "ESCANER",
                "ESCÁNER",
                "INTERFAZ",
                "PINZA SOIC",
                "PINZETAS",
                "SOLDADURA",
                "PASTA PARA SOLDAR",
                "FLUX",
                "MALLA DESOLDAR",
                "CAUTIN",
                "MULTIMETRO",
                "MICROSCOPIO",
                "LUPA",
                "PUNTA LOGICA",
                "PUNTA LÓGICA",
                "FRECUENCIOMETRO",
                "CORTADOR",
                "FRESA",
                "LIMA ",
                "REMACHADORA",
                "COMPUTADORA DE MOTOR",
                "MINI KEY TOOL",
                "EMULADOR",
            ]
        )
    ):
        return "Herramientas y Accesorios"

    # 4. Cerraduras y Candados (Cerraduras de pomo, barra, sobreponer, candados, chapas, cerrojos)
    if (
        re.match(r"^(CAND|CERR-|CER-200|CHAP|CTB|CTE|PH265|PH266|SC014|X-1000|114C|CP-112|FEITELI|MG-\d+MM|AUSTRAL-140|676\d|677\d|175IF|2006)", c_up)
        or o_up == "CANDADOS"
        or any(
            kw in d_up
            for kw in [
                "CANDADO",
                "CERRADURA",
                "CERROJO",
                "CHAPA ",
                "PASADOR",
                "PICAPORTE",
            ]
        )
    ):
        # Si es un cilindro doméstico suelto (CIL-*), evaluar según regla de cilindros domésticos -> Residencial / Seguridad
        if not c_up.startswith("CIL-"):
            return "Cerraduras y Candados"

    # Manejo explícito de Cilindros y Switches (CIL-* / SW-* / MAN-*)
    if c_up.startswith("CIL-") or c_up.startswith("SW-") or "SWITCH" in d_up or "ENCENDIDO" in d_up or "CILINDRO" in d_up:
        if any(m in full for m in ["MOTO", "ITALIKA", "PULSAR", "BAJAJ", "YAMAHA", "KURAZAI", "VENTO"]):
            return "Motos"
        if any(au in full for au in ["DERBY", "JETTA", "OPEL", "CHEVY", "CORSA", "TSURU", "NISSAN", "FORD", "VW", "MANIJA", "MANILA", "ENCENDIDO"]):
            return "Automotriz"
        if any(se in full for se in ["TETRA", "PUNTOS", "MULTIPUNTO", "X720", "AS725", "AS800", "AS549", "IFAM-M"]):
            return "Seguridad / Punto"
        return "Residencial"

    # 5. Ubicación en gaveta manda para forjas/llaves físicas
    loc_dept = dept_from_location(ubicacion)
    if loc_dept in VALID_DEPARTMENTS:
        return loc_dept

    # 6. Clasificación por palabras clave de cerrajería para llaves sin gaveta asignada
    if o_up == "MOTOS" or any(
        m in full for m in ["MOTO", "ITALIKA", "ITA-", "BAJAJ", "BAJ-", "PULSAR", "YAMA-", "SUZU-", "HOND-"]
    ):
        return "Motos"

    if o_up == "SEGURIDAD / PUNTO" or any(
        se in full
        for se in [
            "SEGURIDAD",
            "MULTIPUNTO",
            "LLAVE PUNTOS",
            "DE PUNTOS",
            "TETRA",
            "TUBULAR",
            "ABLOY",
            "PHI-14",
            "PHI-5D",
            "AS200",
            "AS400",
            "AS800",
            "BKY-",
            "AMG-",
            "TOV-",
            "CMX-",
            "XF12",
            "MUL-T-LOCK",
        ]
    ):
        return "Seguridad / Punto"

    if (
        o_up in {"AUTOMOTRIZ", "LLAVES VAT", "SWITCH Y REPUESTOS ENCENDIDO"}
        or re.match(r"^(HK-|A74|A79|A81|A86|A88|A89|A91|F2[A-Z]|FO-|CHR-|DAT-|NSN-|OP-|GM-|TOY-|MIT-|MAZ-|HY-|VA-|HU\d|NE-\d|Y15\d|Y16\d|B10\d|B11\d)", c_up)
        or any(
            au in full
            for au in [
                "LLAVE HUECA",
                "REGATA",
                "AUTOMOTRIZ",
                "VATS",
                "LLAVE VAT",
                "NISSAN",
                "FORD",
                "CHEVROLET",
                "CHEVY",
                "VW",
                "VOLKSWAGEN",
                "JETTA",
                "POINTER",
                "TSURU",
                "CHRYSLER",
                "TOYOTA",
                "MAZDA",
                "MITSUBISHI",
                "HYUNDAI",
                "RENAULT",
                "PEUGEOT",
                "AVEO",
                "SPARK",
                "PLATINA",
                "CORSA",
                "INSERTOS",
                "INSERTO",
            ]
        )
    ):
        return "Automotriz"

    # Por defecto, forja tradicional / llave doméstica va a Residencial
    return "Residencial"


GENERIC_SHORT_NAMES = {
    "LLAVE NIQ JMA",
    "LLAVE NIQUELADA",
    "LLAVE NIQUELADA JMA",
    "LLAVE DEXTER",
    "LLAVE HUECA",
    "LLAVE PUNTOS",
    "LLAVE DECORADA",
    "LLAVE PLASTIFICADA",
    "LLAVE NORMAL",
    "LLAVE",
    "FORJA",
    "PILA",
    "REPUESTO",
    "ALBA",
    "PHILLIPS EMBUTIR",
    "PHILLIPS SOBREPONER",
    "VARIOS COLORES",
    "20MM",
    "25MM",
    "30MM",
    "38MM",
    "50MM",
}


def enrich_product_name(cod: str, nom: str, desc: str) -> str:
    """Asegura que ningún producto quede con nombre ambiguo como solo 'LLAVE NIQ JMA' o 'PILA'."""
    nom_clean = re.sub(r"\s+", " ", (nom or "").strip())
    cod_clean = (cod or "").strip()
    if not nom_clean:
        return cod_clean

    nom_up = nom_clean.upper()
    cod_up = cod_clean.upper()

    if nom_up in GENERIC_SHORT_NAMES or len(nom_clean) <= 5:
        if cod_up and cod_up not in nom_up:
            return f"{cod_clean} - {nom_clean}"
    # Casos donde varios tamaños o acabados comparten nombre idéntico pero distinto código
    if nom_up in {"PROFILE LLAVE NORMAL 60MM", "CANDADO MG LLAVE NORMAL"} and cod_up not in nom_up:
        return f"{cod_clean} - {nom_clean}"

    return nom_clean


def canonical_dedup_key(row: dict) -> str:
    """
    Calcula la llave de agrupación para fusionar productos físicos duplicados:
    1) Alias explícitos de precio público (-P, PUB, SUELTO) creados en Eleventa para el mismo artículo físico.
    2) Misma clave/SKU limpia alfanumérica (ej. FNL-6 == FNL6, FRE-1P == FRE1P, CK-100 == CK100).
    """
    cod = row["codigo"].strip().upper()

    # Alias conocidos de duplicados directos en Eleventa
    EXPLICIT_CANON = {
        "ARILLO-SUELTO": "ARILLOPIEZA",
        "ARILLO-PIEZA": "ARILLOPIEZA",
        "CR-2025 PUB": "CR2025",
        "CR-2025 RENATA": "CR2025",
        "FEITELI-38P": "FEITELI38",
        "FEITELI-38": "FEITELI38",
    }
    if cod in EXPLICIT_CANON:
        return f"SKU:{EXPLICIT_CANON[cod]}"

    # Quitar sufijo explícito ' PUB' o '-P' (cuidando NO afectar llaves automotrices con cabeza plástica sin guion como A89P)
    cod_base = re.sub(r"\s+PUB$", "", cod)
    if re.search(r"-P$", cod_base) and (
        cod_base[:-2].isdigit() or cod_base.startswith("175IF-")
    ):
        cod_base = cod_base[:-2]

    sku_norm = clean_token(cod_base)
    if sku_norm:
        return f"SKU:{sku_norm}"

    return f"RAW:{cod}"


def merge_duplicate_group(group: list, pdf_locations: dict) -> dict:
    """Consolida un grupo de registros duplicados en un único registro maestro limpio."""
    if len(group) == 1:
        base = dict(group[0])
        base["nombre"] = enrich_product_name(base["codigo"], base["nombre"], base["descripcion"])
        if not base["descripcion"]:
            base["descripcion"] = base["nombre"]
        return base

    # Ordenar candidatos para elegir el mejor código maestro:
    # Preferir el que NO termina en '-P' / ' PUB', el que tiene ubicación en PDF, y el más limpio
    def score_master(r):
        c = r["codigo"].strip().upper()
        is_pub_variant = 1 if (c.endswith("-P") or c.endswith(" PUB") or c == "FEITELI-38P" or c == "ARILLO-SUELTO") else 0
        in_pdf = 0 if clean_token(c) in pdf_locations else 1
        has_hyphen_std = 0 if "-" in c else 1
        return (is_pub_variant, in_pdf, has_hyphen_std, len(c), c)

    sorted_grp = sorted(group, key=score_master)
    master = dict(sorted_grp[0])

    # 1. Ubicación prioritaria desde PDF, luego cualquier ubicación válida del grupo
    best_loc = ""
    for r in sorted_grp:
        tok = clean_token(r["codigo"])
        if tok in pdf_locations:
            best_loc = pdf_locations[tok][0]
            break
    if not best_loc:
        for r in sorted_grp:
            if r.get("ubicacion"):
                best_loc = r["ubicacion"]
                break
    master["ubicacion"] = best_loc

    # 2. Molde común (codigo_equivalencia)
    for r in sorted_grp:
        if r.get("codigo_equivalencia"):
            master["codigo_equivalencia"] = r["codigo_equivalencia"]
            break

    # 3. Marca no genérica si existe
    for r in sorted_grp:
        m = (r.get("marca") or "").strip()
        if m and m.lower() not in {"genérica", "generica", "-"}:
            master["marca"] = m
            break

    # 4. Precios: conservar el precio público más alto y si había variante gremio/colega más baja, guardarla en precio_cerrajero
    p_ventas = [parse_float(r.get("precio_venta"), 0.0) for r in sorted_grp if parse_float(r.get("precio_venta"), 0.0) > 0]
    p_compras = [parse_float(r.get("precio_compra"), 0.0) for r in sorted_grp if parse_float(r.get("precio_compra"), 0.0) > 0]
    p_cerrajeros = [parse_opt_float(r.get("precio_cerrajero")) for r in sorted_grp if parse_opt_float(r.get("precio_cerrajero")) is not None]
    p_talleres = [parse_opt_float(r.get("precio_taller")) for r in sorted_grp if parse_opt_float(r.get("precio_taller")) is not None]
    p_mayoreos = [parse_opt_float(r.get("precio_mayoreo")) for r in sorted_grp if parse_opt_float(r.get("precio_mayoreo")) is not None]

    pv_final = max(p_ventas) if p_ventas else 0.0
    pc_final = max(p_compras) if p_compras else 0.0

    # Si se fusionó un par (normal + -P/PUB) con distintos precios de venta, el menor era tarifa gremio/cerrajero
    min_pv = min(p_ventas) if p_ventas else 0.0
    if min_pv > 0 and min_pv < pv_final:
        p_cerrajeros.append(min_pv)

    master["precio_venta"] = round(pv_final, 2)
    master["precio_compra"] = round(pc_final, 2)
    master["precio_cerrajero"] = round(min(p_cerrajeros), 2) if p_cerrajeros else ""
    master["precio_taller"] = round(min(p_talleres), 2) if p_talleres else ""
    master["precio_mayoreo"] = round(min(p_mayoreos), 2) if p_mayoreos else ""

    # 5. Stock actual: sumar existencias positivas válidas (o conservar el mayor si todos <= 0)
    stocks = [parse_float(r.get("stock_actual"), 0.0) for r in sorted_grp]
    pos_stocks = [s for s in stocks if s > 0]
    master["stock_actual"] = round(sum(pos_stocks), 3) if pos_stocks else round(max(stocks), 3)

    # 6. Sumar métricas históricas de venta
    v30_sum = sum(max(0.0, parse_float(r.get("ventas_ultimos_30dias"), 0.0)) for r in sorted_grp)
    tot_sum = sum(max(0.0, parse_float(r.get("total_unidades_vendidas"), 0.0)) for r in sorted_grp)
    ult_fechas = [str(r.get("ultima_venta_at") or "").strip() for r in sorted_grp if str(r.get("ultima_venta_at") or "").strip()]

    master["ventas_ultimos_30dias"] = round(v30_sum, 3)
    master["total_unidades_vendidas"] = round(tot_sum, 3)
    master["ultima_venta_at"] = max(ult_fechas) if ult_fechas else ""

    # Descripción más completa
    best_desc = max((r.get("descripcion", "") for r in sorted_grp), key=len)
    master["descripcion"] = best_desc if best_desc else master["nombre"]
    master["nombre"] = enrich_product_name(master["codigo"], master["nombre"], master["descripcion"])

    return master


def sync_local_storage_json(final_rows: list):
    """Sincroniza C:\\POS\\backend\\data\\storage.json eliminando duplicados/servicios viejos y preservando ventas."""
    if not os.path.exists(STORAGE_JSON_PATH):
        return

    try:
        with open(STORAGE_JSON_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"  [!] No se pudo leer storage.json ({e})")
        return

    old_products = data.get("products", {})
    new_products = {}
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    for r in final_rows:
        pid = r["codigo"]
        prev = old_products.get(pid, {})
        created_at = prev.get("created_at") or now_iso

        prod_obj = {
            "id": pid,
            "codigo_barras": r["codigo"],
            "sku": r["sku"],
            "nombre": r["nombre"],
            "descripcion": r["descripcion"],
            "marca": r["marca"] or "Genérica",
            "precio_compra": parse_float(r["precio_compra"], 0.0),
            "precio_venta": parse_float(r["precio_venta"], 0.0),
            "porcentaje_impuesto": 0.0,
            "departamento": r["departamento"],
            "departamentos_aplicables": r["departamentos_aplicables"],
            "stock_actual": parse_float(r["stock_actual"], 0.0),
            "stock_minimo": parse_float(r["stock_minimo"], 5.0),
            "es_a_granel": int(r["es_a_granel"]),
            "es_servicio": int(r["es_servicio"]),
            "cantidad_insumo": 1.0,
            "ventas_ultimos_30dias": parse_float(r["ventas_ultimos_30dias"], 0.0),
            "total_unidades_vendidas": parse_float(r["total_unidades_vendidas"], 0.0),
            "created_at": created_at,
            "updated_at": now_iso,
        }
        if r["codigo_equivalencia"]:
            prod_obj["codigo_equivalencia"] = r["codigo_equivalencia"]
        if r["ubicacion"]:
            prod_obj["ubicacion"] = r["ubicacion"]
        if parse_opt_float(r["precio_cerrajero"]) is not None:
            prod_obj["precio_cerrajero"] = parse_opt_float(r["precio_cerrajero"])
        if parse_opt_float(r["precio_taller"]) is not None:
            prod_obj["precio_taller"] = parse_opt_float(r["precio_taller"])
        if parse_opt_float(r["precio_mayoreo"]) is not None:
            prod_obj["precio_mayoreo"] = parse_opt_float(r["precio_mayoreo"])
        if parse_opt_float(r["cantidad_mayoreo"]) is not None:
            prod_obj["cantidad_mayoreo"] = parse_opt_float(r["cantidad_mayoreo"])
        if r["ultima_venta_at"]:
            uv = r["ultima_venta_at"]
            if " " in uv and "T" not in uv:
                uv = uv.replace(" ", "T") + "Z"
            prod_obj["ultima_venta_at"] = uv

        new_products[pid] = prod_obj

    data["products"] = new_products
    with open(STORAGE_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"  [OK] Almacén embebido actualizado ({len(new_products)} registros): {STORAGE_JSON_PATH}")


def sync_docker_postgres(final_rows: list):
    """Intenta arrancar pos-postgres en Docker y sincronizar el esquema + catálogo consolidado."""
    try:
        ps_check = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            timeout=8,
        )
        if ps_check.returncode != 0:
            print("  [i] Docker daemon no disponible en este instante; PostgreSQL se sincronizará vía Seeder/Migración Go al iniciar.")
            return
    except Exception:
        print("  [i] Docker CLI no respondió a tiempo; PostgreSQL se sincronizará vía Seeder/Migración Go.")
        return

    containers = [c.strip() for c in ps_check.stdout.splitlines() if c.strip()]
    pg_container = None
    for c in containers:
        if "postgres" in c.lower() or "db" in c.lower():
            pg_container = c
            break

    if not pg_container:
        print("  [i] No se encontró contenedor PostgreSQL en Docker.")
        return

    subprocess.run(["docker", "start", pg_container], capture_output=True, text=True, timeout=15)

    # Construir bloque SQL transaccional para aplicar migración + limpieza + upsert en pos_db
    sql_lines = [
        "BEGIN;",
        "ALTER TABLE productos ADD COLUMN IF NOT EXISTS departamentos_aplicables TEXT NOT NULL DEFAULT 'Todos';",
        "ALTER TABLE detalles_venta ADD COLUMN IF NOT EXISTS insumo_utilizado_id VARCHAR(100);",
        "ALTER TABLE detalles_venta ADD COLUMN IF NOT EXISTS cantidad_insumo_consumida NUMERIC(12, 3) NOT NULL DEFAULT 0.0;",
    ]

    valid_ids = []
    tienda_id = "8377312b-9a2a-4d0f-b74d-f2e0ca6c4d2a"

    def sql_str(s):
        if s is None or str(s).strip() == "":
            return "NULL"
        escaped = str(s).replace("'", "''")
        return f"'{escaped}'"

    def sql_num(v, allow_null=False):
        if allow_null:
            val = parse_opt_float(v)
            return "NULL" if val is None else str(val)
        return str(parse_float(v, 0.0))

    sql_lines.append(
        f"INSERT INTO tiendas (id, clave, nombre, activo) VALUES ('{tienda_id}', 'SUC-001', 'Tienda Principal', true) ON CONFLICT (clave) DO NOTHING;"
    )

    for r in final_rows:
        pid = r["codigo"].replace("'", "''")
        valid_ids.append(f"'{pid}'")
        es_granel_bool = "true" if int(r["es_a_granel"]) == 1 else "false"
        ult_venta = sql_str(r["ultima_venta_at"]) if r["ultima_venta_at"] else "NULL"

        sql_lines.append(
            f"""INSERT INTO productos (
                id, tienda_id, codigo_barras, sku, nombre, descripcion, marca,
                codigo_equivalencia, ubicacion, departamento, departamentos_aplicables,
                precio_compra, precio_venta, precio_cerrajero, precio_taller,
                precio_mayoreo, cantidad_mayoreo, stock_actual, stock_minimo,
                es_a_granel, es_servicio, insumo_vinculado_id, cantidad_insumo,
                ventas_ultimos_30dias, total_unidades_vendidas, ultima_venta_at,
                created_at, updated_at
            ) VALUES (
                '{pid}', '{tienda_id}', {sql_str(r['codigo'])}, {sql_str(r['sku'])},
                {sql_str(r['nombre'])}, {sql_str(r['descripcion'])}, {sql_str(r['marca'] or 'Genérica')},
                {sql_str(r['codigo_equivalencia'])}, {sql_str(r['ubicacion'])},
                {sql_str(r['departamento'])}, {sql_str(r['departamentos_aplicables'] or 'Todos')},
                {sql_num(r['precio_compra'])}, {sql_num(r['precio_venta'])},
                {sql_num(r['precio_cerrajero'], True)}, {sql_num(r['precio_taller'], True)},
                {sql_num(r['precio_mayoreo'], True)}, {sql_num(r['cantidad_mayoreo'], True)},
                {sql_num(r['stock_actual'])}, {sql_num(r['stock_minimo'])},
                {es_granel_bool}, {int(r['es_servicio'])}, NULL, 1.0,
                {sql_num(r['ventas_ultimos_30dias'])}, {sql_num(r['total_unidades_vendidas'])}, {ult_venta},
                NOW(), NOW()
            ) ON CONFLICT (id) DO UPDATE SET
                codigo_barras = EXCLUDED.codigo_barras,
                sku = EXCLUDED.sku,
                nombre = EXCLUDED.nombre,
                descripcion = EXCLUDED.descripcion,
                marca = EXCLUDED.marca,
                codigo_equivalencia = EXCLUDED.codigo_equivalencia,
                ubicacion = EXCLUDED.ubicacion,
                departamento = EXCLUDED.departamento,
                departamentos_aplicables = EXCLUDED.departamentos_aplicables,
                precio_compra = EXCLUDED.precio_compra,
                precio_venta = EXCLUDED.precio_venta,
                precio_cerrajero = EXCLUDED.precio_cerrajero,
                precio_taller = EXCLUDED.precio_taller,
                precio_mayoreo = EXCLUDED.precio_mayoreo,
                cantidad_mayoreo = EXCLUDED.cantidad_mayoreo,
                stock_actual = EXCLUDED.stock_actual,
                stock_minimo = EXCLUDED.stock_minimo,
                es_a_granel = EXCLUDED.es_a_granel,
                es_servicio = EXCLUDED.es_servicio,
                insumo_vinculado_id = NULL,
                ventas_ultimos_30dias = GREATEST(productos.ventas_ultimos_30dias, EXCLUDED.ventas_ultimos_30dias),
                total_unidades_vendidas = GREATEST(productos.total_unidades_vendidas, EXCLUDED.total_unidades_vendidas),
                updated_at = NOW();"""
        )

    # Eliminar servicios individuales antiguos y duplicados obsoletos que no estén referenciados en detalles_venta
    ids_csv = ", ".join(valid_ids)
    sql_lines.append(
        f"""DELETE FROM productos
            WHERE id NOT IN ({ids_csv})
              AND id != 'ART-COMUN'
              AND id NOT IN (SELECT DISTINCT producto_id FROM detalles_venta WHERE producto_id IS NOT NULL);"""
    )
    sql_lines.append("COMMIT;")

    full_sql = "\n".join(sql_lines)
    res = subprocess.run(
        ["docker", "exec", "-i", pg_container, "psql", "-U", "postgres", "-d", "pos_db", "-v", "ON_ERROR_STOP=1"],
        input=full_sql,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=45,
    )
    if res.returncode == 0:
        print(f"  [OK] PostgreSQL en contenedor '{pg_container}' actualizado y depurado con éxito.")
    else:
        print(f"  [!] Advertencia al ejecutar SQL en '{pg_container}': {res.stderr.strip()[:300]}")


def main():
    print("=" * 80)
    print("  ETL DE LIMPIEZA Y CONSOLIDACIÓN PROFUNDA - CATÁLOGO POS CERRAJERÍA")
    print("=" * 80)

    # 0. Respaldo crudo idempotente
    if not os.path.exists(RAW_BACKUP_PATH) and os.path.exists(CSV_PATH):
        shutil.copy2(CSV_PATH, RAW_BACKUP_PATH)
        print(f"[0/5] Respaldo original creado en: {RAW_BACKUP_PATH}")

    source_csv = RAW_BACKUP_PATH if os.path.exists(RAW_BACKUP_PATH) else CSV_PATH
    with open(source_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        raw_rows = list(reader)

    print(f"[1/5] Registros leídos desde fuente: {len(raw_rows)}")

    # 1. Cargar ubicaciones desde Etiquetas1.pdf y Etiquetas2.pdf
    pdf_locations = load_pdf_locations()
    print(f"      Claves con gaveta indexadas desde PDFs: {len(pdf_locations)}")

    # 2. Separar productos físicos reales vs servicios individuales obsoletos
    physical_rows = []
    removed_services = 0

    for r in raw_rows:
        cod = (r.get("codigo") or r.get("sku") or "").strip()
        if not cod:
            continue

        if is_legacy_service_row(r):
            removed_services += 1
            continue

        # Producto físico real (incluyendo los rescatados como BANDA-MG y MEC-TRANSIT)
        r_copy = dict(r)
        r_copy["codigo"] = cod
        r_copy["sku"] = (r.get("sku") or cod).strip()
        r_copy["es_servicio"] = 0

        # Limpiar ubicaciones falsas en adaptadores/memorias con código corto numérico
        orig_depto = (r.get("departamento") or "").strip()
        ubic = format_location_code(r.get("ubicacion") or "")
        tok = clean_token(cod)

        if is_bogus_pdf_location(cod, r.get("nombre", ""), r.get("descripcion", ""), orig_depto):
            ubic = ""
        elif tok in pdf_locations:
            ubic = pdf_locations[tok][0]

        r_copy["ubicacion"] = ubic
        r_copy["departamento"] = classify_physical_department(
            cod=cod,
            nom=r.get("nombre", ""),
            desc=r.get("descripcion", ""),
            ubicacion=ubic,
            orig_depto=orig_depto,
        )
        r_copy["departamentos_aplicables"] = ""
        physical_rows.append(r_copy)

    print(f"[2/5] Servicios individuales obsoletos eliminados: {removed_services}")
    print(f"      Productos físicos candidatos antes de deduplicar: {len(physical_rows)}")

    # 3. Fusión y deduplicación por SKU normalizado / variantes -P / PUB
    sku_groups = defaultdict(list)
    for r in physical_rows:
        key = canonical_dedup_key(r)
        sku_groups[key].append(r)

    dedup_step1 = []
    merged_sku_count = 0
    for key, grp in sku_groups.items():
        if len(grp) > 1:
            merged_sku_count += len(grp) - 1
        dedup_step1.append(merge_duplicate_group(grp, pdf_locations))

    # Segunda pasada: detectar duplicados exactos por (descripcion_normalizada, marca_normalizada, departamento)
    # excluyendo frases genéricas donde el código distingue el modelo
    desc_groups = defaultdict(list)
    for r in dedup_step1:
        desc_norm = re.sub(r"\s+", " ", (r.get("descripcion") or "").strip().upper())
        marca_norm = (r.get("marca") or "GENÉRICA").strip().upper()
        depto = r["departamento"]
        molde = (r.get("codigo_equivalencia") or "").strip().upper()

        # Solo fusionar por descripción si la descripción es suficientemente específica (>18 chars),
        # no contiene códigos distintos explícitos y comparten mismo molde (o ninguno tiene molde distinto)
        is_generic = (
            desc_norm in GENERIC_SHORT_NAMES
            or len(desc_norm) < 18
            or any(
                g in desc_norm
                for g in [
                    "LLAVE NIQ",
                    "LLAVE DEXTER",
                    "LLAVE HUECA",
                    "LLAVE PUNTOS",
                    "LLAVE DECORADA",
                    "LLAVE PLASTIFICADA",
                    "PROFILE LLAVE",
                    "CANDADO MG",
                    "CILINDRO",
                    "ADAPTADOR",
                    "MEMORIA",
                ]
            )
        )
        if is_generic:
            desc_groups[f"UNIQUE:{r['codigo']}"].append(r)
        else:
            desc_groups[f"DESC:{depto}|{marca_norm}|{molde}|{desc_norm}"].append(r)

    consolidated_physical = []
    merged_desc_count = 0
    for key, grp in desc_groups.items():
        if len(grp) > 1:
            merged_desc_count += len(grp) - 1
        consolidated_physical.append(merge_duplicate_group(grp, pdf_locations))

    # Ordenar productos físicos por departamento y luego código
    consolidated_physical.sort(key=lambda x: (x["departamento"], x["codigo"]))

    print(f"[3/5] Duplicados fusionados por clave/variante: {merged_sku_count}")
    print(f"      Duplicados fusionados por descripción+marca: {merged_desc_count}")
    print(f"      Total productos físicos únicos consolidados: {len(consolidated_physical)}")

    # 4. Agregar los Servicios Maestros Configurables por Departamento
    final_rows = []
    fieldnames = [
        "codigo",
        "sku",
        "nombre",
        "descripcion",
        "marca",
        "codigo_equivalencia",
        "ubicacion",
        "departamento",
        "departamentos_aplicables",
        "precio_compra",
        "precio_venta",
        "precio_cerrajero",
        "precio_taller",
        "precio_mayoreo",
        "cantidad_mayoreo",
        "stock_actual",
        "stock_minimo",
        "es_a_granel",
        "es_servicio",
        "ventas_ultimos_30dias",
        "total_unidades_vendidas",
        "ultima_venta_at",
    ]

    for r in consolidated_physical + MASTER_SERVICES:
        assert r["departamento"] in VALID_DEPARTMENTS, f"Departamento inválido: {r['departamento']}"
        clean_row = {
            "codigo": str(r.get("codigo", "")).strip(),
            "sku": str(r.get("sku") or r.get("codigo", "")).strip(),
            "nombre": str(r.get("nombre", "")).strip(),
            "descripcion": str(r.get("descripcion") or r.get("nombre", "")).strip(),
            "marca": str(r.get("marca") or "Genérica").strip(),
            "codigo_equivalencia": str(r.get("codigo_equivalencia") or "").strip(),
            "ubicacion": str(r.get("ubicacion") or "").strip(),
            "departamento": str(r.get("departamento", "Residencial")).strip(),
            "departamentos_aplicables": str(r.get("departamentos_aplicables") or "").strip(),
            "precio_compra": round(parse_float(r.get("precio_compra"), 0.0), 2),
            "precio_venta": round(parse_float(r.get("precio_venta"), 0.0), 2),
            "precio_cerrajero": (
                round(parse_opt_float(r.get("precio_cerrajero")), 2)
                if parse_opt_float(r.get("precio_cerrajero")) is not None
                else ""
            ),
            "precio_taller": (
                round(parse_opt_float(r.get("precio_taller")), 2)
                if parse_opt_float(r.get("precio_taller")) is not None
                else ""
            ),
            "precio_mayoreo": (
                round(parse_opt_float(r.get("precio_mayoreo")), 2)
                if parse_opt_float(r.get("precio_mayoreo")) is not None
                else ""
            ),
            "cantidad_mayoreo": (
                round(parse_opt_float(r.get("cantidad_mayoreo")), 2)
                if parse_opt_float(r.get("cantidad_mayoreo")) is not None
                else ""
            ),
            "stock_actual": round(parse_float(r.get("stock_actual"), 0.0), 3),
            "stock_minimo": round(parse_float(r.get("stock_minimo"), 5.0), 2),
            "es_a_granel": 1 if str(r.get("es_a_granel", "0")).strip() == "1" else 0,
            "es_servicio": 1 if str(r.get("es_servicio", "0")).strip() == "1" else 0,
            "ventas_ultimos_30dias": round(parse_float(r.get("ventas_ultimos_30dias"), 0.0), 3),
            "total_unidades_vendidas": round(parse_float(r.get("total_unidades_vendidas"), 0.0), 3),
            "ultima_venta_at": str(r.get("ultima_venta_at") or "").strip(),
        }
        final_rows.append(clean_row)

    print(f"[4/5] Servicios Maestros agregados: {len(MASTER_SERVICES)}")
    print(f"      Total catálogo limpio final: {len(final_rows)} registros")

    # Resumen por departamento
    dept_counts = Counter(r["departamento"] for r in final_rows)
    print("\n      Distribución final por Departamento:")
    for dep, cnt in sorted(dept_counts.items(), key=lambda x: (-x[1], x[0])):
        print(f"        - {dep:28s}: {cnt:4d}")

    # 5. Guardar CSV en migracion y assets + actualizar storage.json y PostgreSQL
    print("\n[5/5] Guardando artefactos y sincronizando bases de datos...")
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(final_rows)
    print(f"  [OK] Guardado: {CSV_PATH}")

    os.makedirs(os.path.dirname(ASSETS_CSV_PATH), exist_ok=True)
    shutil.copy2(CSV_PATH, ASSETS_CSV_PATH)
    print(f"  [OK] Sincronizado a Flutter assets: {ASSETS_CSV_PATH}")

    sync_local_storage_json(final_rows)
    sync_docker_postgres(final_rows)

    print("\n" + "=" * 80)
    print("  LIMPIEZA PROFUNDA COMPLETADA CON ÉXITO")
    print("=" * 80)


if __name__ == "__main__":
    main()
