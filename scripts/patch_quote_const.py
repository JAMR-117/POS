with open(r'C:\POS\client\lib\presentation\widgets\quote_dialog.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    "Flexible(child: Text('Folio: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),",
    "Flexible(child: Text('Folio: $folio', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),"
)

with open(r'C:\POS\client\lib\presentation\widgets\quote_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print('Patched folio text successfully')
