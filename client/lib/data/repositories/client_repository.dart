import 'dart:convert';
import 'dart:math';
import '../local/database_helper.dart';
import '../local/models.dart';
import 'package:sqflite/sqflite.dart';

typedef ClientModel = Cliente;

class ClientRepository {
  final DatabaseHelper _dbHelper;

  ClientRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  String _generateUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Búsqueda y filtrado de clientes activos
  Future<List<Cliente>> getClients([String query = '']) async {
    final db = await _dbHelper.database;
    final cleanQuery = query.trim();
    
    final results = await db.query(
      'clientes',
      where: cleanQuery.isEmpty ? 'activo = 1' : 'activo = 1 AND (nombre LIKE ? OR rfc_o_dni LIKE ? OR telefono LIKE ?)',
      whereArgs: cleanQuery.isEmpty ? null : ['%$cleanQuery%', '%$cleanQuery%', '%$cleanQuery%'],
      orderBy: 'nombre ASC',
      limit: 50,
    );
    return results.map((r) => Cliente.fromMap(r)).toList();
  }

  /// Guardar o actualizar cliente completo con campos CFDI / Fiscales
  Future<void> saveClient(Cliente client) async {
    final db = await _dbHelper.database;
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'clientes',
      {
        ...client.toMap(),
        'created_at': isoNow,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Eliminación lógica de cliente
  Future<void> deleteClient(String clienteId) async {
    final db = await _dbHelper.database;
    await db.update(
      'clientes',
      {'activo': 0},
      where: 'id = ?',
      whereArgs: [clienteId],
    );
  }

  /// Consulta de abonos realizados por el cliente (Estado de cuenta)
  Future<List<Map<String, dynamic>>> getClientAbonos(String clienteId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'abonos_credito',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'fecha DESC',
      limit: 50,
    );
  }

  /// Registra un abono a la cuenta del cliente y lo refleja en movimientos de caja
  Future<void> registrarAbono({
    String? abonoId,
    required String clienteId,
    required double monto,
    String? corteCajaId,
  }) async {
    final db = await _dbHelper.database;
    final id = abonoId ?? _generateUUID();
    final isoNow = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // 1. Insertar abono
      await txn.insert('abonos_credito', {
        'id': id,
        'cliente_id': clienteId,
        'corte_caja_id': corteCajaId ?? 'S/C',
        'monto': monto,
        'fecha': isoNow,
      });

      // 2. Registrar movimiento de entrada en caja
      if (corteCajaId != null && corteCajaId.isNotEmpty && corteCajaId != 'S/C') {
        await txn.insert('movimientos_caja', {
          'id': 'MOV_ABONO_${DateTime.now().microsecondsSinceEpoch}',
          'corte_caja_id': corteCajaId,
          'tipo': 'entrada',
          'monto': monto,
          'concepto': 'Abono a cuenta cliente $clienteId',
          'fecha': isoNow,
        });
      }

      // 3. Descontar saldo deudor asegurando que no sea negativo
      final updated = await txn.rawUpdate(
        'UPDATE clientes SET saldo_deudor = MAX(0, saldo_deudor - ?) WHERE id = ?',
        [monto, clienteId],
      );

      if (updated == 0) throw Exception('Cliente no encontrado o inactivo para registro de abono.');

      // 4. Outbox sync
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
        'retry_count': 0,
        'created_at': isoNow,
      });
    });
  }
}