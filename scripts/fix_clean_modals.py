import os, re

# 1. catalog_import_dialog.dart
with open(r'C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Make sure content has ConstrainedBox + SingleChildScrollView and properly closed
old_block = """      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column("""
if old_block in c:
    # check actions
    c = re.sub(
        r'(\s*\]\s*\}\s*,\s*actions:\s*\[)',
        r'\n            ]\n          ),\n        ),\n      ),\n      actions: [',
        c,
        flags=re.MULTILINE
    )
    # or direct replace around actions
    idx = c.find('      actions: [')
    if idx != -1:
        prefix = c[:idx].rstrip()
        # count open vs close
        print(f"catalog_import_dialog prefix ends with: {repr(prefix[-30:])}")

with open(r'C:\POS\client\lib\presentation\widgets\catalog_import_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print("Check 1 done")
