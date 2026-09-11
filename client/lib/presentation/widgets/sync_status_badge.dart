import 'package:flutter/material.dart';
import '../../data/sync/sync_models.dart';
import '../../data/sync/sync_worker.dart';

class SyncStatusBadge extends StatelessWidget {
  final SyncWorker syncWorker;

  const SyncStatusBadge({super.key, required this.syncWorker});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: syncWorker,
      builder: (context, _) {
        final status = syncWorker.status;
        final pending = syncWorker.pendingCount;

        Color badgeColor;
        IconData badgeIcon;
        String label;

        switch (status) {
          case SyncStatusState.synced:
            badgeColor = const Color(0xFF2E7D32); // Verde
            badgeIcon = Icons.cloud_done;
            label = 'En línea';
            break;
          case SyncStatusState.syncing:
            badgeColor = const Color(0xFF0288D1); // Azul
            badgeIcon = Icons.sync;
            label = 'Sincronizando...';
            break;
          case SyncStatusState.pendingSync:
            badgeColor = const Color(0xFFF57C00); // Naranja advertencia
            badgeIcon = Icons.cloud_upload;
            label = 'Pendientes: $pending';
            break;
          case SyncStatusState.offline:
            badgeColor = const Color(0xFFD32F2F); // Rojo
            badgeIcon = Icons.cloud_off;
            label = pending > 0 ? 'Sin red ($pending)' : 'Sin red';
            break;
        }

        return Tooltip(
          message: 'Estado de sincronización central (Fase 3 Outbox)',
          child: InkWell(
            onTap: () => syncWorker.processPendingQueue(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: badgeColor.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 14, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}