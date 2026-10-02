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
  final double totalEfectivoEsperado; // Fondo inicial + Ventas Efectivo - Retiros

  const ShiftSummary({
    required this.shiftId,
    required this.montoInicial,
    required this.ventasEfectivo,
    required this.ventasTarjeta,
    required this.ventasTransferencia,
    required this.totalVentas,
    required this.totalTickets,
    required this.totalEfectivoEsperado,
  });
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

    // Consulta de todas las ventas del corte
    final salesRows = await db.query(
      'ventas',
      columns: ['total', 'pagos_desglose'],
      where: 'corte_caja_id = ?',
      whereArgs: [shiftId],
    );

    double sumEfectivo = 0.0;
    double sumTarjeta = 0.0;
    double sumTransferencia = 0.0;
    double sumTotal = 0.0;

    for (final row in salesRows) {
      sumTotal += (row['total'] as num).toDouble();
      final desgloseJson = row['pagos_desglose'] as String;
      final List<dynamic> payments = jsonDecode(desgloseJson);

      for (final p in payments) {
        final method = (p['metodo'] as String).toLowerCase();
        final amount = (p['monto'] as num).toDouble();

        if (method == 'efectivo') {
          sumEfectivo += amount;
        } else if (method == 'tarjeta') {
          sumTarjeta += amount;
        } else {
          sumTransferencia += amount;
        }
      }
    }

    final esperadoEnCaja = shift.montoInicial + sumEfectivo - shift.montoRetiros;

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
        'id': movementId,
        'event_type': 'MOVIMIENTO_CAJA',
        'payload': payload,
        'sync_status': 'pending',
        'retry_count': 0,
        'created_at': isoNow,
      });
    });
  }

    return ShiftSummary(
      shiftId: shiftId,
      montoInicial: shift.montoInicial,
      ventasEfectivo: _roundTo2(sumEfectivo),
      ventasTarjeta: _roundTo2(sumTarjeta),
      ventasTransferencia: _roundTo2(sumTransferencia),
      totalVentas: _roundTo2(sumTotal),
      totalTickets: salesRows.length,
      totalEfectivoEsperado: _roundTo2(esperadoEnCaja),
    );
  }

  /// Retorna el reporte acumulado del turno en curso (Corte X) sin cerrar la sesión
  Future<ShiftSummary> generateCorteX(String shiftId) async {
    return await getShiftSummary(shiftId);
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