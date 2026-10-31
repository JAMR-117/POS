import os

pos_screen_path = r'C:\POS\client\lib\presentation\screens\pos_screen.dart'
with open(pos_screen_path, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Fix badge text
target_badge = "'✏️ Insumo ocupado:  pza [Cambiar]'"
replacement_badge = "'🔧 ✏️ Insumo ocupado: ${(item.cantidadInsumoConsumida % 1 == 0 ? item.cantidadInsumoConsumida.toInt() : item.cantidadInsumoConsumida)} pza${(item.insumoUtilizadoNombre != null && item.insumoUtilizadoNombre!.isNotEmpty) ? \" (${item.insumoUtilizadoNombre})\" : \"\"} [Cambiar]'"

if target_badge in c:
    c = c.replace(target_badge, replacement_badge)
    print("BADGE REPLACED SUCCESS")
else:
    print("BADGE NOT FOUND")

with open(pos_screen_path, 'w', encoding='utf-8') as f:
    f.write(c)
