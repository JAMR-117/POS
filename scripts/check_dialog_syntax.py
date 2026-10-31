import os

files = [
    r"C:\POS\client\lib\presentation\widgets\cash_movement_dialog.dart",
    r"C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart",
    r"C:\POS\client\lib\presentation\widgets\stock_adjustment_dialog.dart",
    r"C:\POS\client\lib\presentation\widgets\common_article_dialog.dart",
    r"C:\POS\client\lib\presentation\widgets\edit_service_line_dialog.dart",
    r"C:\POS\client\lib\presentation\screens\clients_screen.dart",
    r"C:\POS\client\lib\presentation\screens\inventory_screen.dart",
]

for path in files:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    open_p = content.count('(')
    close_p = content.count(')')
    open_b = content.count('{')
    close_b = content.count('}')
    open_sq = content.count('[')
    close_sq = content.count(']')
    print(f"{os.path.basename(path)}: ( diff={open_p - close_p}, {{ diff={open_b - close_b}, [ diff={open_sq - close_sq}")
