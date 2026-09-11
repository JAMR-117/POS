import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'sync_models.dart';

class SyncApiException implements Exception {
  final String message;
  final int? statusCode;
  SyncApiException(this.message, {this.statusCode});

  @override
  String toString() => 'SyncApiException: $message (Status: $statusCode)';
}

class SyncApiClient {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  SyncApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 5), // Fail-fast estricto
  }) : _client = client ?? http.Client();

  /// Despacha un lote de eventos al backend central en Go (/api/v1/sync)
  Future<SyncBatchResponse> sendBatch(List<SyncEvent> events) async {
    if (events.isEmpty) {
      return SyncBatchResponse(acknowledgedIds: []);
    }

    final endpoint = Uri.parse('$baseUrl/api/v1/sync');
    final requestBody = jsonEncode({
      'batch_size': events.length,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'events': events.map((e) => e.toJson()).toList(),
    });

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 207) {
        final Map<String, dynamic> decoded = jsonDecode(response.body);
        return SyncBatchResponse.fromJson(decoded);
      } else {
        throw SyncApiException(
          'El backend rechazó el lote: ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } on SocketException catch (e) {
      throw SyncApiException('Sin conexión física o host inalcanzable: ${e.message}');
    } on TimeoutException {
      throw SyncApiException('Tiempo de espera agotado al despachar lote (Timeout).');
    } catch (e) {
      if (e is SyncApiException) rethrow;
      throw SyncApiException('Fallo inesperado de transporte: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}