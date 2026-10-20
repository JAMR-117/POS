# Reporte de Migración Inteligente y Limpieza de Catálogo POS

**Fecha de Ejecución:** 2026-10-20 11:51:59  
**Archivos Fuente Procesados:**
- `inventario_eleventa.xls` (Inventario histórico de Eleventa/CARprog)
- `Etiquetas1.pdf` (Posiciones y gavetas recién etiquetadas físicamente)
- `Etiquetas2.pdf` (Matriz digitalizada de gavetas y coordenadas)

---

## 1. Métricas Generales del Proceso ETL
- **Total de productos leídos desde Eleventa:** 909
- **Método de lectura aplicado:** `pd.read_csv (sep='	', encoding='latin-1')`
- **Total de productos exportados al nuevo POS:** 909
- **Ubicaciones actualizadas prioritariamente desde PDFs:** 140
- **Ubicaciones recuperadas desde descripciones históricas:** 120
- **Total de productos con ubicación física asignada:** 260
- **Productos clasificados como Servicios (`es_servicio = 1`):** 136
- **Productos físicos con control de inventario (`es_servicio = 0`):** 773

---

## 2. Unificación de Moldes Cerrajeros (`codigo_equivalencia`)
- **Total de productos con Molde Raíz asignado:** 597
- **Total de Grupos Únicos de Moldes Creados:** 406
- **Ejemplo Maestro R52:**
  - Todas las variantes (`PHI-52`, `R-52`, `R52E`, `DEX-52`, `52`, `R52-AL`, `R52-DECORADA`, `R52D`, `R52G`, `R52P`) comparten de forma unificada: **`codigo_equivalencia = 'R52'`**.
- **Ejemplo Maestro R52L:**
  - Todas las variantes (`PHI-52L`, `R52L`, `R52LE`, `DEX-52L`, `R52LD`, `R52LP`) comparten: **`codigo_equivalencia = 'R52L'`**.
- **Ejemplos Phillips Puntos:**
  - Familia `PHI-14D`, `PHI-14DE`, `AS200` comparten: **`codigo_equivalencia = 'PHI-14D'`**.
  - Familia `PHI-5D`, `PHI-5DE`, `AS400`, `6329` comparten: **`codigo_equivalencia = 'PHI-5D'`**.

---

## 3. Distribución por Departamentos
| departamento                       |   count |
|:-----------------------------------|--------:|
| Residencial                        |     239 |
| Automotriz                         |     222 |
| Servicios                          |     112 |
| Seguridad / Punto                  |      60 |
| Cerraduras                         |      58 |
| Motos                              |      48 |
| Herramientas                       |      37 |
| Candados                           |      19 |
| Programadores                      |      15 |
| Accesorios / Pilas                 |      15 |
| Taller                             |      13 |
| General                            |      10 |
| Argolla metalica y arillo plastico |      10 |
| Accesorios electronica             |       9 |
| Switch y repuestos encendido       |       4 |
| GUIAS                              |       4 |
| Interfaces                         |       4 |
| socket y adaptador UPA             |       3 |
| ADAPTADORES                        |       3 |
| UPA Programador                    |       3 |
| Actuadores                         |       2 |
| Alarmas                            |       2 |
| Computadoras y tableros            |       2 |
| Punta lógica                       |       2 |
| Aceite aflojatodo                  |       2 |
| Socket y adaptador universal       |       2 |
| Adaptador GQ                       |       1 |
| Llaveros y accesorios              |       1 |
| Memorias                           |       1 |
| OBDII                              |       1 |
| Pinzas soic8                       |       1 |
| Llaves VAT                         |       1 |
| Frecuenciometro                    |       1 |
| Emuladores                         |       1 |
| Xhorse                             |       1 |

---

## 4. Distribución por Marcas Detectadas
| marca                           |   count |
|:--------------------------------|--------:|
| Genérica                        |     539 |
| JMA                             |     110 |
| Alba                            |      93 |
| Dexter                          |      39 |
| Lishi                           |      20 |
| Phillips                        |      18 |
| Ford                            |      18 |
| Económica (Dexter/Austral/Yale) |      13 |
| Austral                         |      11 |
| Silca                           |       7 |
| Honda                           |       7 |
| Toyota                          |       6 |
| Nissan                          |       5 |
| Ilco                            |       3 |
| Yamaha                          |       3 |
| Italika                         |       3 |
| KEYDIY                          |       3 |
| Xhorse                          |       3 |
| Yale                            |       2 |
| Chrysler                        |       2 |

---

## 5. Muestra de Registros Migrados
|    | codigo    | nombre                                            | marca    | codigo_equivalencia   | ubicacion   | departamento           |   precio_venta |   stock_actual |
|---:|:----------|:--------------------------------------------------|:---------|:----------------------|:------------|:-----------------------|---------------:|---------------:|
|  0 | 114C      | CANDADO PHILLIPS GANCHO CORTO                     | Phillips |                       |             | Candados               |          160   |              1 |
|  1 | 13770     | DADO 10MM DE 3/8 LARGO TRUPER                     | Truper   |                       |             | Herramientas           |           55   |              2 |
|  2 | 1560      | (CAT-2) LLAVE ILCO CATERPILLAR                    | Ilco     | 1560                  |             | Residencial            |            7   |             10 |
|  3 | 15743     | LLAVE 10MM COMBINADA CON MATRACA                  | Genérica |                       |             | Herramientas           |           99   |              2 |
|  4 | 175IF-I   | CERRADURA IZQUIERDA INSTAFACIL PHILLIPS           | Phillips |                       |             | Cerraduras             |          120   |              1 |
|  5 | 175IF-I-P | CERRADURA IZQUIERDA INSTAFACIL                    | Genérica |                       |             | Cerraduras             |          190   |              0 |
|  6 | 2006      | CERRADURA PERFIL ALUMINIO GRIS                    | Genérica |                       |             | Cerraduras             |          250   |              1 |
|  7 | 2006-P    | CERRADURA PERFIL ALUMINIO                         | Genérica |                       |             | Cerraduras             |          295   |              6 |
|  8 | 2007      | CERRADURA PERFIL ALUMINIO BLANCO                  | Genérica |                       |             | Cerraduras             |          250   |              0 |
|  9 | 22        | MALLA PARA DESOLDAR                               | Genérica |                       |             | Accesorios electronica |           39   |              2 |
| 10 | 37        | SOLDADURA 100 GRAMOS 60/40                        | Genérica |                       |             | General                |          259   |              7 |
| 11 | 4192 DUP  | DUPLICADO (R1)                                    | Genérica | R1                    |             | Servicios              |           20   |             48 |
| 12 | 4192      | LLAVE DEXTER TIPO R1                              | Dexter   | R1                    |             | Residencial            |            3.5 |             20 |
| 13 | 550MM     | CERRADURA PHILLIPS 550 MANIJA MANIJA ALUMINIO NAT | Phillips |                       |             | Cerraduras             |          360   |              0 |
| 14 | 6496      | CERRADURA PARA VITRINA DEXTER                     | Dexter   |                       |             | Cerraduras             |          100   |              6 |

---
*Reporte generado automáticamente por `scripts/etl_migracion.py`.*
