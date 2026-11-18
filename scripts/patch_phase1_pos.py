import re

pos_path = r'C:\POS\client\lib\presentation\screens\pos_screen.dart'
with open(pos_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update _handleBarcodeScan logic
old_scan_pattern = r"    final results = await widget\.cartController\.scanOrSearchProduct\(text\);[\r\n\s]+if \(results\.length > 1 && mounted\) \{[\r\n\s]+_showIncrementalSearchResults\(results\);[\r\n\s]+\} else if \(results\.length == 1 && mounted\) \{[\r\n\s]+await _handleSelectedCatalogItem\(results\.first\);[\r\n\s]+\} else if \(results\.isEmpty && mounted\) \{"
new_scan_code = """    final results = await widget.cartController.scanOrSearchProduct(text);

    if (!mounted) return;

    if (results.length == 1) {
      await _handleSelectedCatalogItem(results.first);
    } else if (results.length > 1) {
      await _openAdvancedProductSearch(initialQuery: text);
    } else if (results.isEmpty) {"""

content, count1 = re.subn(old_scan_pattern, new_scan_code, content)
print(f"Replaced scan logic: {count1}")

# 2. Remove _showIncrementalSearchResults
old_modal_pattern = r"  /// Despliega el modal de selección de coincidencias y variantes por molde[\r\n\s]+void _showIncrementalSearchResults\(List<Product> products\) \{[\s\S]+?\}\.then\(\(_\) => _refocusSearch\(\)\);[\r\n]+"
content, count2 = re.subn(old_modal_pattern, "", content)
print(f"Removed _showIncrementalSearchResults: {count2}")

with open(pos_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print("Updated pos_screen.dart")
