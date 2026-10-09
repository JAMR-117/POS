import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../local/database_helper.dart';

class ClientModel {
  final String id;
  final String nombre;
  final String? rfcODni;
  final String? telefono;
  final double limiteCredito;
  final double saldoDeudor;

  ClientModel({
    required this.id,
    required this.nombre,
    this.rfcODni,
    this.telefono,
    this.limiteCredito = 0.0,
    this.saldoDeudor = 0.0,
  });

  factory ClientModel.fromMap(Map<String, dynamic> map) {
    return ClientModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      rfcODni: map['rfc_o_dni'] as String?,
      telefono: map['telefono'] as String?,
      limiteCredito: (map['limite_credito'] as num).toDouble(),
      saldoDeudor: (map['saldo_deudor'] as num).toDouble(),
    );
  }
}

class ClientRepository {
  final DatabaseHelper _dbHelper;

  ClientRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  String _generateUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Búsqueda y filtrado de clientes activos
  Future<List<ClientModel>> getClients([String query = '']) async {
    final db = await _dbHelper.database;
    final cleanQuery = query.trim();
    
    final results = await db.query(
      'clientes',
      where: cleanQuery.isEmpty ? 'activo = 1' : 'activo = 1 AND (nombre LIKE ? OR rfc_o_dni LIKE ?)',
      whereArgs: cleanQuery.isEmpty ? null : ['%$cleanQuery%', '%$cleanQuery%'],
      orderBy: 'nombre ASC',
      limit: 20,
    );
    return results.map((r) => ClientModel.fromMap(r)).toList();
  }

  /// Registra un pago a la deuda del cliente y emite el evento al servidor
  Future<void> registrarAbono({
    String? abonoId, // Opcional, si no se envía, se genera uno
    required String clienteId,
    required double monto,
    String? corteCajaId, // Recomendado para trazabilidad en corte Z
  }) async {
    final db = await _dbHelper.database;
    final id = abonoId ?? _generateUUID();
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // 1. Insertar historial de pago
      await txn.insert('abonos_credito', {
        'id': id,
        'cliente_id': clienteId,
        'corte_caja_id': corteCajaId ?? 'S/C',
        'monto': monto,
        'fecha': isoNow,
      });

      // 2. Descontar la deuda atómicamente asegurando que no baje de cero
      final updated = await txn.rawUpdate(
        'UPDATE clientes SET saldo_deudor = MAX(0, saldo_deudor - ?) WHERE id = ?',
        [monto, clienteId]
      );

      if (updated == 0) throw Exception('Cliente no encontrado o inactivo para registro de abono.');

      // 3. Patrón Outbox: Emitir a cola de sincronización para consolidación en servidor Go
      final payload = jsonEncode({
        'abono_id': id,
        'cliente_id': clienteId,
        'monto': monto,
        'fecha': isoNow,
      });

      await txn.insert('sync_queue', {
        'id': id,
        'event_type': 'ABONO_REGISTRADO',
        'payload': payload,
        'sync_status': 'pending',
        'retry_count': 0, // Inclusión defensiva de la columna retry_count
        'created_at': isoNow,
      });
    });
  }
}