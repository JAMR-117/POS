/// Utilidades seguras para manipulación de cadenas en el POS.
/// Previene errores `RangeError` cuando se truncan IDs cortos (ej. 'R-52'),
/// folios o prefijos de búsqueda.
String safeSubstring(String text, int start, [int? end]) {
  if (text.isEmpty) return '';
  final int len = text.length;
  final int safeStart = start < 0 ? 0 : (start > len ? len : start);
  if (safeStart >= len) return '';

  if (end == null) {
    return text.substring(safeStart);
  }

  final int safeEnd = end < safeStart ? safeStart : (end > len ? len : end);
  if (safeEnd <= safeStart) return '';

  return text.substring(safeStart, safeEnd);
}

extension SafeStringExtension on String {
  /// Retorna los primeros [maxChars] caracteres de forma segura sin lanzar RangeError.
  String safePrefix(int maxChars) {
    if (maxChars <= 0 || isEmpty) return '';
    return length > maxChars ? safeSubstring(this, 0, maxChars) : this;
  }

  /// Subcadena segura con límites acotados automáticamente al rango válido [0..length].
  String safeSub(int start, [int? end]) => safeSubstring(this, start, end);
}
