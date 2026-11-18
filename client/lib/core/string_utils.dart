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

/// Convierte un monto numérico a su representación en letra en Pesos Mexicanos (M.N.)
String numeroALetras(double monto) {
  if (monto < 0) return 'MENOS ${numeroALetras(-monto)}';
  final int entero = monto.floor();
  final int centavos = ((monto - entero) * 100).round();
  final String centavosStr = centavos.toString().padLeft(2, '0');

  if (entero == 0) {
    return 'CERO PESOS $centavosStr/100 M.N.';
  }

  String letras = _convertirGrupo(entero);
  final String moneda = entero == 1 ? 'PESO' : 'PESOS';
  return '$letras $moneda $centavosStr/100 M.N.'.toUpperCase();
}

String _convertirGrupo(int n) {
  if (n == 0) return '';
  if (n == 1) return 'UN';
  if (n < 1000) return _convertirCentenas(n);
  if (n < 2000) return 'UN MIL ${_convertirCentenas(n % 1000)}'.trim();
  if (n < 1000000) {
    final miles = n ~/ 1000;
    final resto = n % 1000;
    return '${_convertirCentenas(miles)} MIL ${_convertirCentenas(resto)}'.trim();
  }
  if (n < 2000000) {
    final resto = n % 1000000;
    return 'UN MILLÓN ${_convertirGrupo(resto)}'.trim();
  }
  final millones = n ~/ 1000000;
  final resto = n % 1000000;
  return '${_convertirCentenas(millones)} MILLONES ${_convertirGrupo(resto)}'.trim();
}

String _convertirCentenas(int n) {
  if (n == 0) return '';
  if (n == 100) return 'CIEN';
  if (n > 100 && n < 200) return 'CIENTO ${_convertirDecenas(n % 100)}'.trim();

  final centenas = [
    '',
    'CIENTO',
    'DOSCIENTOS',
    'TRESCIENTOS',
    'CUATROCIENTOS',
    'QUINIENTOS',
    'SEISCIENTOS',
    'SETECIENTOS',
    'OCHOCIENTOS',
    'NOVECIENTOS'
  ];

  final c = n ~/ 100;
  final resto = n % 100;
  if (c > 0) {
    return '${centenas[c]} ${_convertirDecenas(resto)}'.trim();
  }
  return _convertirDecenas(resto);
}

String _convertirDecenas(int n) {
  if (n == 0) return '';
  if (n <= 15) {
    const basicos = [
      '',
      'UN',
      'DOS',
      'TRES',
      'CUATRO',
      'CINCO',
      'SEIS',
      'SIETE',
      'OCHO',
      'NUEVE',
      'DIEZ',
      'ONCE',
      'DOCE',
      'TRECE',
      'CATORCE',
      'QUINCE'
    ];
    return basicos[n];
  }
  if (n < 20) return 'DIECI${_convertirDecenas(n - 10)}';
  if (n == 20) return 'VEINTE';
  if (n < 30) return 'VEINTI${_convertirDecenas(n - 20)}';

  final decenas = [
    '',
    '',
    'VEINTE',
    'TREINTA',
    'CUARENTA',
    'CINCUENTA',
    'SESENTA',
    'SETENTA',
    'OCHENTA',
    'NOVENTA'
  ];

  final d = n ~/ 10;
  final resto = n % 10;
  if (resto == 0) return decenas[d];
  return '${decenas[d]} Y ${_convertirDecenas(resto)}';
}
