import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';

/// Modelo de datos para representar el estado de un turno en SQLite
class ShiftRecord {
  final String id;
  final int? folioCorte;
  final String usuarioId;
  final double montoInicial;
  final double montoVentasEfectivo;
  final double montoVentasTarjeta;
  final double montoVentasOtros;
  final double montoRetiros;
  final String tipoCorte; // 'X' o 'Z'
  final double discrepancia;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final String estado; // 'abierto' o 'cerrado'

  const ShiftRecord({
    required this.id,
    this.folioCorte,
    required this.usuarioId,
    required this.montoInicial,
    required this.montoVentasEfectivo,
    required this.montoVentasTarjeta,
    required this.montoVentasOtros,
    required this.montoRetiros,
    required this.tipoCorte,
    required this.discrepancia,
    required this.fechaApertura,
    this.fechaCierre,
    required this.estado,
  });

  factory ShiftRecord.fromMap(Map<String, dynamic> map) {
    return ShiftRecord(
      id: map['id'] as String,
      folioCorte: map['folio_corte'] as int?,
      usuarioId: map['usuario_id'] as String,
      montoInicial: (map['monto_inicial'] as num).toDouble(),
      montoVentasEfectivo: (map['monto_ventas_efectivo'] as num).toDouble(),
      montoVentasTarjeta: (map['monto_ventas_tarjeta'] as num).toDouble(),
      montoVentasOtros: (map['monto_ventas_otros'] as num).toDouble(),
      montoRetiros: (map['monto_retiros'] as num).toDouble(),
      tipoCorte: map['tipo_corte'] as String,
      discrepancia: (map['discrepancia'] as num).toDouble(),
      fechaApertura: DateTime.parse(map['fecha_apertura'] as String),
      fechaCierre: map['fecha_cierre'] != null ? DateTime.parse(map['fecha_cierre'] as String) : null,
      estado: map['estado'] as String,
    );
  }
}

/// Consolidado analítico de cobros dentro de la ventana de tiempo del turno
class ShiftSummary {
  final String shiftId;
  final double montoInicial;
  final double ventasEfectivo;
  final double ventasTarjeta;
  final double ventasTransferencia;
  final double totalVentas;
  final int totalTickets;
  final double totalEfectivoEsperado; // Fondo inicial + Ventas Efectivo + Entradas - Salidas
  final double entradasEfectivo;
  final double salidasEfectivo;
  final double gananciaEstimada;
  final Map<String, double> ventasPorDepartamento;

  const ShiftSummary({
    required this.shiftId,
    required this.montoInicial,
    required this.ventasEfectivo,
    required this.ventasTarjeta,
    required this.ventasTransferencia,
    required this.totalVentas,
    required this.totalTickets,
    required this.totalEfectivoEsperado,
    this.entradasEfectivo = 0.0,
    this.salidasEfectivo = 0.0,
    this.gananciaEstimada = 0.0,
    this.ventasPorDepartamento = const {},
  });

  bool get isConsolidatedDay => shiftId.startsWith('DIA-');
}

class ShiftRepository {
  final DatabaseHelper _dbHelper;

  ShiftRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Obtiene el turno activo si existe
  Future<ShiftRecord?> getActiveShift() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'cortes_caja',
      where: "estado = 'abierto'",
      orderBy: 'fecha_apertura DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      return ShiftRecord.fromMap(results.first);
    }
    return null;
  }

  /// Registra la apertura de caja e inserta el evento inicial en Outbox
  Future<ShiftRecord> openShift({
    required String usuarioId,
    required double montoInicial,
  }) async {
    final db = await _dbHelper.database;
    final shiftId = _generateUUID();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final active = await getActiveShift();
    if (active != null) {
      throw Exception('Ya existe un turno abierto (${active.id}). Debe cerrarlo antes de iniciar otro.');
    }

    final newShift = ShiftRecord(
      id: shiftId,
      usuarioId: usuarioId,
      montoInicial: _roundTo2(montoInicial),
      montoVentasEfectivo: 0.0,
      montoVentasTarjeta: 0.0,
      montoVentasOtros: 0.0,
      montoRetiros: 0.0,
      tipoCorte: 'X',
      discrepancia: 0.0,
      fechaApertura: DateTime.parse(nowIso),
      estado: 'abierto',
    );

    await db.transaction((txn) async {
      await txn.insert(
        'cortes_caja',
        {
          'id': newShift.id,
          'folio_corte': null,
          'usuario_id': newShift.usuarioId,
          'monto_inicial': newShift.montoInicial,
          'monto_ventas_efectivo': 0.0,
          'monto_ventas_tarjeta': 0.0,
          'monto_ventas_otros': 0.0,
          'monto_retiros': 0.0,
          'tipo_corte': 'X',
          'discrepancia': 0.0,
          'fecha_apertura': nowIso,
          'fecha_cierre': null,
          'estado': 'abierto',
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final outboxPayload = jsonEncode({
        'corte_caja_id': newShift.id,
        'usuario_id': newShift.usuarioId,
        'monto_inicial': newShift.montoInicial,
        'fecha_apertura': nowIso,
      });

      await txn.insert(
        'sync_queue',
        {
          'id': _generateUUID(),
          'event_type': 'TURNO_ABIERTO',
          'payload': outboxPayload,
          'sync_status': 'pending',
          'retry_count': 0,
          'error_code': null,
          'created_at': nowIso,
          'synced_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });

    return newShift;
  }

  /// Calcula en memoria/SQLite las ventas del turno leyendo pagos_desglose
  Future<ShiftSummary> getShiftSummary(String shiftId) async {
    final db = await _dbHelper.database;

    final shiftRows = await db.query(
      'cortes_caja',
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );

    if (shiftRows.isEmpty) {
      throw Exception('El turno $shiftId no fue encontrado.');
    }

    final shift = ShiftRecord.fromMap(shiftRows.first);

    // Consulta de todas las ventas no canceladas del corte
    final salesRows = await db.query(
      'ventas',
      columns: ['total', 'pagos_desglose'],
      where: "corte_caja_id = ? AND estatus != 'cancelado'",
      whereArgs: [shiftId],
    );

    double sumEfectivo = 0.0;
    double sumTarjeta = 0.0;
    double sumTransferencia = 0.0;
    double sumTotal = 0.0;

    for (final row in salesRows) {
      final t = (row['total'] as num?)?.toDouble() ?? 0.0;
      sumTotal += t;
      final rawDesglose = row['pagos_desglose'];

      if (rawDesglose != null && rawDesglose is String && rawDesglose.trim().isNotEmpty) {
        try {
          final List<dynamic> payments = jsonDecode(rawDesglose);
          for (final p in payments) {
            final method = ((p['metodo'] ?? '') as String).toLowerCase();
            final amount = (p['monto'] as num?)?.toDouble() ?? 0.0;

            if (method.contains('efectivo')) {
              sumEfectivo += amount;
            } else if (method.contains('tarjeta')) {
              sumTarjeta += amount;
            } else {
              sumTransferencia += amount;
            }
          }
        } catch (_) {
          sumEfectivo += t;
        }
      } else {
        sumEfectivo += t;
      }
    }

    // Abonos a crédito cobrados durante este turno
    double abonosEfectivo = 0.0;
    try {
      final abonosRows = await db.rawQuery(
        'SELECT COALESCE(SUM(monto), 0.0) as total_abonos FROM abonos_credito WHERE corte_caja_id = ?',
        [shiftId],
      );
      if (abonosRows.isNotEmpty) {
        abonosEfectivo = (abonosRows.first['total_abonos'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    // Movimientos de entrada / salida de caja
    final movRows = await db.query(
      'movimientos_caja',
      where: 'corte_caja_id = ?',
      whereArgs: [shiftId],
    );
    double entradas = 0.0;
    double salidas = 0.0;
    for (final m in movRows) {
      final tipo = m['tipo'] as String;
      final monto = (m['monto'] as num?)?.toDouble() ?? 0.0;
      if (tipo == 'entrada') {
        entradas += monto;
      } else {
        salidas += monto;
      }
    }

    // Desglose de ventas por departamento y cálculo de costo/ganancia con LEFT JOIN
    final deptoRows = await db.rawQuery('''
      SELECT COALESCE(p.departamento, 'General') as depto,
             COALESCE(SUM(dv.total_linea), 0.0) as total_depto,
             COALESCE(SUM(dv.cantidad * dv.costo_historico), 0.0) as costo_depto
      FROM detalles_venta dv
      LEFT JOIN productos p ON dv.producto_id = p.id
      JOIN ventas v ON dv.venta_id = v.id
      WHERE v.corte_caja_id = ? AND v.estatus != 'cancelado'
      GROUP BY COALESCE(p.departamento, 'General')
    ''', [shiftId]);

    final Map<String, double> deptoMap = {};
    double totalCostos = 0.0;
    for (final r in deptoRows) {
      final String d = r['depto'] as String;
      final double totalD = (r['total_depto'] as num?)?.toDouble() ?? 0.0;
      final double costoD = (r['costo_depto'] as num?)?.toDouble() ?? 0.0;
      deptoMap[d] = _roundTo2(totalD);
      totalCostos += costoD;
    }

    final double ganancia = _roundTo2(sumTotal - totalCostos);
    final double retirosTotales = shift.montoRetiros > 0 ? shift.montoRetiros : salidas;
    final double esperadoEnCaja = shift.montoInicial + sumEfectivo + abonosEfectivo + entradas - retirosTotales;

    return ShiftSummary(
      shiftId: shiftId,
      montoInicial: shift.montoInicial,
      ventasEfectivo: _roundTo2(sumEfectivo),
      ventasTarjeta: _roundTo2(sumTarjeta),
      ventasTransferencia: _roundTo2(sumTransferencia),
      totalVentas: _roundTo2(sumTotal),
      totalTickets: salesRows.length,
      totalEfectivoEsperado: _roundTo2(esperadoEnCaja),
      entradasEfectivo: _roundTo2(entradas),
      salidasEfectivo: _roundTo2(retirosTotales),
      gananciaEstimada: ganancia,
      ventasPorDepartamento: deptoMap,
    );
  }

  /// Retorna el reporte acumulado del turno en curso (Corte X) sin cerrar la sesión
  Future<ShiftSummary> generateCorteX(String shiftId) async {
    return await getShiftSummary(shiftId);
  }

  /// Consulta el consolidado global de ventas del dia actual (util para Administradores
  /// o cuando no existe un turno individual de cajero abierto).
  Future<ShiftSummary> getDailyConsolidatedSummary({String? usuarioId}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final whereClause = usuarioId != null
        ? "(DATE(fecha_venta, 'localtime') = DATE('now', 'localtime') OR fecha_venta LIKE '$todayStr%') AND estatus != 'cancelado' AND usuario_id = ?"
        : "(DATE(fecha_venta, 'localtime') = DATE('now', 'localtime') OR fecha_venta LIKE '$todayStr%') AND estatus != 'cancelado'";
    final whereArgs = usuarioId != null ? [usuarioId] : null;

    final salesRows = await db.query(
      'ventas',
      columns: ['total', 'pagos_desglose'],
      where: whereClause,
      whereArgs: whereArgs,
    );

    double sumEfectivo = 0.0;
    double sumTarjeta = 0.0;
    double sumTransferencia = 0.0;
    double sumTotal = 0.0;

    for (final row in salesRows) {
      final t = (row['total'] as num?)?.toDouble() ?? 0.0;
      sumTotal += t;
      final rawDesglose = row['pagos_desglose'];

      if (rawDesglose != null && rawDesglose is String && rawDesglose.trim().isNotEmpty) {
        try {
          final List<dynamic> payments = jsonDecode(rawDesglose);
          for (final p in payments) {
            final method = ((p['metodo'] ?? '') as String).toLowerCase();
            final amount = (p['monto'] as num?)?.toDouble() ?? 0.0;

            if (method.contains('efectivo')) {
              sumEfectivo += amount;
            } else if (method.contains('tarjeta')) {
              sumTarjeta += amount;
            } else {
              sumTransferencia += amount;
            }
          }
        } catch (_) {
          sumEfectivo += t;
        }
      } else {
        sumEfectivo += t;
      }
    }

    // Abonos del dia
    double abonosEfectivo = 0.0;
    try {
      final abonosRows = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0.0) as total_abonos FROM abonos_credito WHERE (DATE(fecha_abono, 'localtime') = DATE('now', 'localtime') OR fecha_abono LIKE '$todayStr%')",
      );
      if (abonosRows.isNotEmpty) {
        abonosEfectivo = (abonosRows.first['total_abonos'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    // Movimientos del dia
    double entradas = 0.0;
    double salidas = 0.0;
    try {
      final movRows = await db.rawQuery(
        "SELECT tipo, COALESCE(SUM(monto), 0.0) as total_monto FROM movimientos_caja WHERE (DATE(fecha_movimiento, 'localtime') = DATE('now', 'localtime') OR fecha_movimiento LIKE '$todayStr%') GROUP BY tipo",
      );
      for (final m in movRows) {
        final tipo = m['tipo'] as String;
        final monto = (m['total_monto'] as num?)?.toDouble() ?? 0.0;
        if (tipo == 'entrada') {
          entradas += monto;
        } else {
          salidas += monto;
        }
      }
    } catch (_) {}

    // Desglose de departamentos del dia
    final deptoRows = await db.rawQuery('''
      SELECT COALESCE(p.departamento, 'General') as depto,
             COALESCE(SUM(dv.total_linea), 0.0) as total_depto,
             COALESCE(SUM(dv.cantidad * dv.costo_historico), 0.0) as costo_depto
      FROM detalles_venta dv
      LEFT JOIN productos p ON dv.producto_id = p.id
      JOIN ventas v ON dv.venta_id = v.id
      WHERE (DATE(v.fecha_venta, 'localtime') = DATE('now', 'localtime') OR v.fecha_venta LIKE '$todayStr%') AND v.estatus != 'cancelado'
      GROUP BY COALESCE(p.departamento, 'General')
    ''');

    final Map<String, double> deptoMap = {};
    double totalCostos = 0.0;
    for (final r in deptoRows) {
      final String d = r['depto'] as String;
      final double totalD = (r['total_depto'] as num?)?.toDouble() ?? 0.0;
      final double costoD = (r['costo_depto'] as num?)?.toDouble() ?? 0.0;
      deptoMap[d] = _roundTo2(totalD);
      totalCostos += costoD;
    }

    final double ganancia = _roundTo2(sumTotal - totalCostos);
    final double retirosTotales = salidas;
    final double esperadoEnCaja = sumEfectivo + abonosEfectivo + entradas - retirosTotales;

    return ShiftSummary(
      shiftId: 'DIA-$todayStr',
      montoInicial: 0.0,
      ventasEfectivo: _roundTo2(sumEfectivo),
      ventasTarjeta: _roundTo2(sumTarjeta),
      ventasTransferencia: _roundTo2(sumTransferencia),
      totalVentas: _roundTo2(sumTotal),
      totalTickets: salesRows.length,
      totalEfectivoEsperado: _roundTo2(esperadoEnCaja),
      entradasEfectivo: _roundTo2(entradas),
      salidasEfectivo: _roundTo2(retirosTotales),
      gananciaEstimada: ganancia,
      ventasPorDepartamento: deptoMap,
    );
  }

  /// Cierre atómico del turno (Corte Z) y generación del evento Outbox
  Future<void> closeShiftCorteZ({
    required String shiftId,
    required double efectivoContado,
  }) async {
    final db = await _dbHelper.database;
    final summary = await getShiftSummary(shiftId);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // discrepancia = Efectivo Real Contado - Efectivo Esperado Teórico
    // Positivo = Sobrante (+), Negativo = Faltante (-)
    final discrepancia = _roundTo2(efectivoContado - summary.totalEfectivoEsperado);

    await db.transaction((txn) async {
      // 1. Congelar estado del turno a 'cerrado'
      final updated = await txn.update(
        'cortes_caja',
        {
          'monto_ventas_efectivo': summary.ventasEfectivo,
          'monto_ventas_tarjeta': summary.ventasTarjeta,
          'monto_ventas_otros': summary.ventasTransferencia,
          'tipo_corte': 'Z',
          'discrepancia': discrepancia,
          'fecha_cierre': nowIso,
          'estado': 'cerrado',
        },
        where: "id = ? AND estado = 'abierto'",
        whereArgs: [shiftId],
      );

      if (updated == 0) {
        throw Exception('El turno ya se encuentra cerrado o no existe.');
      }

      // 2. Empaquetar payload contable
      final outboxPayload = jsonEncode({
        'corte_caja_id': shiftId,
        'tipo_corte': 'Z',
        'totales': {
          'monto_inicial': summary.montoInicial,
          'ventas_efectivo': summary.ventasEfectivo,
          'ventas_tarjeta': summary.ventasTarjeta,
          'ventas_otros': summary.ventasTransferencia,
          'total_ventas': summary.totalVentas,
          'total_tickets': summary.totalTickets,
          'efectivo_esperado': summary.totalEfectivoEsperado,
          'efectivo_declarado': _roundTo2(efectivoContado),
          'discrepancia': discrepancia,
        },
        'fecha_cierre': nowIso,
      });

      // 3. Encolar evento para el SyncWorker
      await txn.insert(
        'sync_queue',
        {
          'id': shiftId, // Idempotencia amarrada al ID del turno
          'event_type': 'CORTE_CAJA_REGISTRADO',
          'payload': outboxPayload,
          'sync_status': 'pending',
          'retry_count': 0,
          'error_code': null,
          'created_at': nowIso,
          'synced_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  /// Registra una entrada o salida de efectivo, actualiza el corte y genera el evento Outbox
  Future<void> registerCashMovement({
    required String shiftId,
    required String tipo, // 'entrada' o 'salida'
    required double monto,
    required String concepto,
  }) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();
    final movementId = _generateUUID();

    await db.transaction((txn) async {
      // 0. Validación de Integridad de Caja
      if (monto <= 0) {
        throw Exception('El monto del movimiento debe ser estrictamente mayor a 0.');
      }
      if (concepto.trim().length < 3) {
        throw Exception('El concepto debe contener al menos 3 caracteres reales.');
      }

      if (tipo == 'salida') {
        // Consultar fondo inicial del turno activo
        final shiftRows = await txn.query('cortes_caja', where: 'id = ?', whereArgs: [shiftId]);
        if (shiftRows.isEmpty) throw Exception('No se encontró el turno activo para registrar el movimiento.');
        final double montoInicial = (shiftRows.first['monto_inicial'] as num?)?.toDouble() ?? 0.0;

        // Sumar ventas en efectivo
        final salesRows = await txn.query('ventas', where: "corte_caja_id = ? AND estatus != 'cancelado'", whereArgs: [shiftId]);
        double ventasEfectivo = 0.0;
        for (final s in salesRows) {
          final desglose = s['pagos_desglose'] as String? ?? '{}';
          try {
            final pMap = jsonDecode(desglose) as Map<String, dynamic>;
            ventasEfectivo += (pMap['efectivo'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }

        // Sumar entradas y salidas previas
        final movRows = await txn.query('movimientos_caja', where: 'corte_caja_id = ?', whereArgs: [shiftId]);
        double entradas = 0.0;
        double salidas = 0.0;
        for (final m in movRows) {
          final t = m['tipo'] as String;
          final amt = (m['monto'] as num).toDouble();
          if (t == 'entrada') {
            entradas += amt;
          } else {
            salidas += amt;
          }
        }

        final double efectivoDisponibleEnCaja = montoInicial + ventasEfectivo + entradas - salidas;
        if (monto > efectivoDisponibleEnCaja + 0.001) {
          throw Exception('Fondos insuficientes en caja: El monto de salida (\$${monto.toStringAsFixed(2)}) no puede exceder el efectivo disponible (\$${efectivoDisponibleEnCaja.toStringAsFixed(2)}).');
        }
      }

      // 1. Insertar el movimiento histórico
      await txn.insert('movimientos_caja', {
        'id': movementId,
        'corte_caja_id': shiftId,
        'tipo': tipo,
        'monto': monto,
        'concepto': concepto,
        'fecha': isoNow,
      });

      // 2. Actualizar el acumulado en cortes_caja
      // Salidas suman a monto_retiros, Entradas restan a monto_retiros.
      final double signo = tipo == 'salida' ? 1.0 : -1.0;
      
      final updated = await txn.rawUpdate('''
        UPDATE cortes_caja 
        SET monto_retiros = monto_retiros + ? 
        WHERE id = ?
      ''', [monto * signo, shiftId]);
      
      if (updated == 0) {
        throw Exception('No se encontró el turno activo para registrar el movimiento.');
      }

      // 3. Patrón Outbox: Generar evento de sincronización
      final payload = jsonEncode({
        'movimiento_id': movementId,
        'corte_caja_id': shiftId,
        'tipo': tipo,
        'monto': monto,
        'concepto': concepto,
        'fecha': isoNow,
      });

      await txn.insert('sync_queue', {
        'id': movementId, // Idempotencia
        'event_type': 'MOVIMIENTO_CAJA',
        'payload': payload,
        'sync_status': 'pending',
        'retry_count': 0,
        'created_at': isoNow,
      });
    });
  }

  double _roundTo2(double val) {
    return (val * 100).roundToDouble() / 100;
  }

  String _generateUUID() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}