import 'dart:convert';

/// Representación en memoria de un registro de sync_queue
class SyncEvent {
  final String id;
  final String eventType;
  final Map<String, dynamic> payload;
  final int retryCount;
  final DateTime createdAt;

  SyncEvent({
    required this.id,
    required this.eventType,
    required this.payload,
    this.retryCount = 0,
    required this.createdAt,
  });

  factory SyncEvent.fromMap(Map<String, dynamic> map) {
    return SyncEvent(
      id: map['id'] as String,
      eventType: map['event_type'] as String,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_type': eventType,
      'payload': payload,
      'retry_count': retryCount,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// Respuesta estructurada emitida por el endpoint /api/v1/sync de Go
class SyncBatchResponse {
  final List<String> acknowledgedIds;
  final Map<String, String> errors; // Key: event_id, Value: error_code

  SyncBatchResponse({
    required this.acknowledgedIds,
    this.errors = const {},
  });

  factory SyncBatchResponse.fromJson(Map<String, dynamic> json) {
    final acks = (json['acks'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final errMap = <String, String>{};
    if (json['errors'] is Map<String, dynamic>) {
      (json['errors'] as Map<String, dynamic>).forEach((k, v) {
        errMap[k] = v.toString();
      });
    }

    return SyncBatchResponse(acknowledgedIds: acks, errors: errMap);
  }
}

/// Estados reactivos visibles para el cajero
enum SyncStatusState {
  synced,       // Todo al día con el servidor
  pendingSync,  // Hay ventas en cola local pendientes de despachar
  offline,      // Sin conexión a la red central
  syncing,      // Despachando lote en este instante
}