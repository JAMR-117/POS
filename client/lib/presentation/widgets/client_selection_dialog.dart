import 'package:flutter/material.dart';
import '../../data/local/models.dart';
import '../../data/repositories/client_repository.dart';

class ClientSelectionDialog extends StatefulWidget {
  final VoidCallback? onNavigateToClientsModule;

  const ClientSelectionDialog({
    super.key,
    this.onNavigateToClientsModule,
  });

  static Future<Cliente?> show(
    BuildContext context, {
    VoidCallback? onNavigateToClientsModule,
  }) {
    return showDialog<Cliente>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ClientSelectionDialog(
        onNavigateToClientsModule: onNavigateToClientsModule,
      ),
    );
  }

  @override
  State<ClientSelectionDialog> createState() => _ClientSelectionDialogState();
}

class _ClientSelectionDialogState extends State<ClientSelectionDialog> {
  final ClientRepository _repo = ClientRepository();
  final TextEditingController _searchController = TextEditingController();
  List<Cliente> _clients = [];
  bool _isLoading = true;

  static final Cliente _defaultPublicoGral = Cliente(
    id: 'PUBLICO-GRAL',
    nombre: 'Público en General',
    limiteCredito: 0.0,
    saldoDeudor: 0.0,
    tarifaPreferencial: 'Público',
  );

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients([String query = '']) async {
    setState(() => _isLoading = true);
    try {
      final results = await _repo.getClients(query);
      if (mounted) {
        setState(() {
          _clients = results;
        });
      }
    } catch (e) {
      debugPrint('Error cargando clientes: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getTariffColor(String tariff) {
    switch (tariff.toLowerCase()) {
      case 'cerrajero':
        return const Color(0xFF0D47A1);
      case 'taller':
        return const Color(0xFF4A148C);
      case 'mayoreo':
        return const Color(0xFFE65100);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  Future<void> _showQuickNewClientDialog() async {
    final nombreCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final rfcCtrl = TextEditingController();
    String tarifa = 'Público';
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<Cliente>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setQuickState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add_alt_1, color: Color(0xFF1F4E79)),
                SizedBox(width: 8),
                Text('Nuevo Cliente Rápido', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nombreCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nombre / Razón Social *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: telCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / WhatsApp (Opcional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: rfcCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'RFC / Identificación (Opcional)',
                        prefixIcon: Icon(Icons.fingerprint),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tarifa,
                      decoration: const InputDecoration(
                        labelText: 'Tarifa Asignada',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Público', child: Text('Público (Estándar)')),
                        DropdownMenuItem(value: 'Cerrajero', child: Text('Cerrajero')),
                        DropdownMenuItem(value: 'Taller', child: Text('Taller Mecánico')),
                        DropdownMenuItem(value: 'Mayoreo', child: Text('Mayoreo')),
                      ],
                      onChanged: (v) {
                        if (v != null) setQuickState(() => tarifa = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Crear y Asignar'),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final newClient = Cliente(
                    id: 'cli-${DateTime.now().millisecondsSinceEpoch}',
                    nombre: nombreCtrl.text.trim(),
                    telefono: telCtrl.text.trim().isNotEmpty ? telCtrl.text.trim() : null,
                    rfcODni: rfcCtrl.text.trim().isNotEmpty ? rfcCtrl.text.trim().toUpperCase() : null,
                    tarifaPreferencial: tarifa,
                    limiteCredito: 0.0,
                    saldoDeudor: 0.0,
                    activo: true,
                  );
                  await _repo.saveClient(newClient);
                  if (ctx.mounted) Navigator.pop(ctx, newClient);
                },
              ),
            ],
          );
        },
      ),
    );

    if (created != null && mounted) {
      Navigator.of(context).pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = 520.0.clamp(320.0, screenSize.width * 0.95);
    final dialogHeight = 540.0.clamp(380.0, screenSize.height * 0.85);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.people_alt_outlined, color: Color(0xFF1F4E79), size: 24),
              SizedBox(width: 10),
              Text(
                'Asignar Cliente al Ticket',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1F4E79)),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Botón directo para seleccionar / restablecer Público en General
            Material(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pop(_defaultPublicoGral),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFF2E7D32),
                        child: Icon(Icons.storefront, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Público en General',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B5E20)),
                            ),
                            Text(
                              'Venta regular en mostrador (Tarifa Público sin crédito)',
                              style: TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DEFAULT',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Barra de búsqueda instantánea
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por nombre, teléfono o RFC...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadClients();
                        },
                      )
                    : null,
              ),
              onChanged: (val) => _loadClients(val),
            ),
            const SizedBox(height: 10),

            // Botones de acción rápida: Nuevo Cliente Rápido + Ir al Módulo F2
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F4E79),
                      side: const BorderSide(color: Color(0xFF1F4E79)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('➕ Nuevo Cliente Rápido', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _showQuickNewClientDialog,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF455A64),
                      side: const BorderSide(color: Color(0xFFB0BEC5)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('👥 Ir a Clientes [F2]', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onNavigateToClientsModule?.call();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Lista de clientes
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _clients.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_off_outlined, size: 40, color: Colors.grey),
                                const SizedBox(height: 8),
                                const Text(
                                  'No se encontraron clientes registrados.',
                                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Registrar cliente ahora'),
                                  onPressed: _showQuickNewClientDialog,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _clients.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = _clients[index];
                            if (c.id == 'PUBLICO-GRAL') {
                              return const SizedBox.shrink();
                            }
                            final tariffColor = _getTariffColor(c.tarifaPreferencial);
                            final hasDebt = c.saldoDeudor > 0;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF1F4E79).withValues(alpha: 0.1),
                                child: const Icon(Icons.person, color: Color(0xFF1F4E79), size: 20),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.nombre,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: tariffColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: tariffColor.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      c.tarifaPreferencial,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: tariffColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  if (c.telefono != null && c.telefono!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8.0),
                                      child: Text(
                                        '📞 ${c.telefono}',
                                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                                      ),
                                    ),
                                  if (c.rfcODni != null && c.rfcODni!.isNotEmpty)
                                    Text(
                                      'RFC: ${c.rfcODni}',
                                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    hasDebt
                                        ? '-\$${c.saldoDeudor.toStringAsFixed(2)}'
                                        : '\$0.00',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
                                    ),
                                  ),
                                  Text(
                                    hasDebt ? 'Deuda' : 'Al corriente',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: hasDebt ? Colors.red.shade600 : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.of(context).pop(c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
