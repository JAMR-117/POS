dialog_path = r'C:\POS\client\lib\presentation\widgets\product_or_service_action_dialog.dart'
with open(dialog_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "labelText: 'Precio P" in line and "($) *" in line:
        line = "                  labelText: 'Precio Publico *',\n"
    elif "labelText: 'Cerrajero ($)'" in line:
        line = "                  labelText: 'Precio Cerrajero',\n"
    elif "labelText: 'Taller ($)'" in line:
        line = "                  labelText: 'Precio Taller',\n"
    elif "labelText: 'Mayoreo ($)'" in line:
        line = "                  labelText: 'Precio Mayoreo',\n"
    new_lines.append(line)

with open(dialog_path, 'w', encoding='utf-8', newline='\n') as f:
    f.writelines(new_lines)
print('Done fixing labelTexts line by line')
