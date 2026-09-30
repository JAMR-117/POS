import 'dart:convert';
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

  Future<List<ClientModel>> getClients([String query = '']) async {
    final db = await _dbHelper.database;
    final cleanQuery = query.trim();
    
    final results = await db.query(
      'clientes',
      where: cleanQuery.isEmpty ? 'activo = 1' : 'activo = 1 AND nombre LIKE ?',
      whereArgs: cleanQuery.isEmpty ? null : ['%$cleanQuery%'],
      orderBy: 'nombre ASC',
    );
    return results.map((r) => ClientModel.fromMap(r)).toList();
  }

  /// Inserta un abono, actualiza el saldo del cliente y encola el evento Outbox
  Future<void> registrarAbono({
    required String abonoId,
    required String clienteId,
    required double monto,
  }) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // 1. Insertar registro del abono
      await txn.insert('abonos_credito', {
        'id': abonoId,
        'cliente_id': clienteId,
        'monto': monto,
        'fecha': isoNow,
      });

      // 2. Reducir saldo deudor
      final updated = await txn.rawUpdate(
        'UPDATE clientes SET saldo_deudor = MAX(0, saldo_deudor - ?) WHERE id = ?',
        [monto, clienteId]
      );

      if (updated == 0) throw Exception('Cliente no encontrado');

      // 3. Patrón Outbox
      final payload = jsonEncode({
        'abono_id': abonoId,
        'cliente_id': clienteId,
        'monto': monto,
        'fecha': isoNow,
      });

      await txn.insert('sync_queue', {
        'id': abonoId,
        'event_type': 'ABONO_REGISTRADO',
        'payload': payload,
        'sync_status': 'pending',
        'created_at': isoNow,
      });
    });
  }
}