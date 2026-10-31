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

  /// Obtiene la cronología completa de movimientos del cliente (Compras Contado/Crédito, Abonos y Cancelaciones)
  Future<List<ClientMovementItem>> getClientAccountHistory(String clienteId) async {
    final db = await _dbHelper.database;
    final List<ClientMovementItem> movements = [];

    // 1. Obtener ventas atribuidas al cliente (completadas y canceladas)
    final salesRows = await db.query(
      'ventas',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'fecha_venta DESC',
    );

    for (final s in salesRows) {
      final ventaId = s['id'] as String;
      final folio = s['folio_ticket'] as String? ?? 'S/F';
      final total = (s['total'] as num?)?.toDouble() ?? 0.0;
      final estatus = (s['estatus'] as String? ?? 'completado').toLowerCase();
      final fechaStr = s['fecha_venta'] as String? ?? DateTime.now().toIso8601String();
      final fecha = DateTime.tryParse(fechaStr) ?? DateTime.now();
      final pagosRaw = s['pagos_desglose'] as String? ?? '[]';
      final corteCajaId = s['corte_caja_id'] as String?;

      List<dynamic> pagos = [];
      try {
        pagos = jsonDecode(pagosRaw) as List<dynamic>;
      } catch (_) {}

      // Determinar si es crédito o contado
      bool esCredito = false;
      final List<String> metodos = [];
      for (final p in pagos) {
        if (p is Map<String, dynamic>) {
          final m = p['metodo']?.toString() ?? '';
          if (m.isNotEmpty) metodos.add(m);
          if (m.toLowerCase().contains('crédit') || m.toLowerCase().contains('credit')) {
            esCredito = true;
          }
        }
      }
      final formaPagoStr = metodos.isNotEmpty ? metodos.join(', ') : (esCredito ? 'Crédito' : 'Contado');

      // Obtener partidas de la venta
      final detailRows = await db.query(
        'detalles_venta',
        where: 'venta_id = ?',
        whereArgs: [ventaId],
      );

      final List<Map<String, dynamic>> partidas = [];
      for (final d in detailRows) {
        final prodId = d['producto_id'] as String? ?? '';
        final prodRow = await db.query(
          'productos',
          columns: ['nombre', 'descripcion'],
          where: 'id = ?',
          whereArgs: [prodId],
          limit: 1,
        );
        final prodNombre = prodRow.isNotEmpty
            ? (prodRow.first['nombre'] as String? ?? prodRow.first['descripcion'] as String? ?? prodId)
            : prodId;

        partidas.add({
          'id': d['id'],
          'producto_id': prodId,
          'nombre': prodNombre,
          'cantidad': (d['cantidad'] as num?)?.toDouble() ?? 1.0,
          'precio_historico': (d['precio_historico'] as num?)?.toDouble() ?? 0.0,
          'total_linea': (d['total_linea'] as num?)?.toDouble() ?? 0.0,
          'insumo_utilizado_id': d['insumo_utilizado_id'],
          'cantidad_insumo_consumida': (d['cantidad_insumo_consumida'] as num?)?.toDouble() ?? 0.0,
        });
      }

      ClientMovementType tipo;
      String concepto;
      if (estatus == 'cancelado') {
        tipo = ClientMovementType.ticketCancelado;
        concepto = 'Ticket Cancelado ($folio)';
      } else if (esCredito) {
        tipo = ClientMovementType.compraCredito;
        concepto = 'Compra a Crédito ($folio)';
      } else {
        tipo = ClientMovementType.compraContado;
        concepto = 'Compra de Contado ($folio)';
      }

      movements.add(ClientMovementItem(
        id: ventaId,
        folio: folio,
        fecha: fecha,
        tipo: tipo,
        concepto: concepto,
        monto: total,
        formaPago: formaPagoStr,
        partidas: partidas,
        corteCajaId: corteCajaId,
      ));
    }

    // 2. Obtener abonos realizados por el cliente
    final abonosRows = await db.query(
      'abonos_credito',
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'fecha DESC',
    );

    for (final a in abonosRows) {
      final abonoId = a['id'] as String;
      final monto = (a['monto'] as num?)?.toDouble() ?? 0.0;
      final fechaStr = a['fecha'] as String? ?? DateTime.now().toIso8601String();
      final fecha = DateTime.tryParse(fechaStr) ?? DateTime.now();
      final corteCajaId = a['corte_caja_id'] as String?;

      movements.add(ClientMovementItem(
        id: abonoId,
        folio: null,
        fecha: fecha,
        tipo: ClientMovementType.abonoPago,
        concepto: 'Abono / Pago a Cuenta',
        monto: monto,
        formaPago: 'Efectivo / Caja',
        partidas: [],
        corteCajaId: corteCajaId,
      ));
    }

    // 3. Ordenar cronológicamente descendente (más reciente primero)
    movements.sort((a, b) => b.fecha.compareTo(a.fecha));
    return movements;
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