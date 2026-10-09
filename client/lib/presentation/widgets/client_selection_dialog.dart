import 'package:flutter/material.dart';
import '../../data/repositories/client_repository.dart';

class ClientSelectionDialog extends StatefulWidget {
  const ClientSelectionDialog({super.key});

  static Future<ClientModel?> show(BuildContext context) {
    return showDialog<ClientModel>(
      context: context,
      builder: (_) => const ClientSelectionDialog(),
    );
  }

  @override
  State<ClientSelectionDialog> createState() => _ClientSelectionDialogState();
}

class _ClientSelectionDialogState extends State<ClientSelectionDialog> {
  final ClientRepository _repo = ClientRepository();
  final TextEditingController _searchController = TextEditingController();
  List<ClientModel> _clients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients([String query = '']) async {
    setState(() => _isLoading = true);
    try {
      final results = await _repo.getClients(query);
      if (mounted) {
        setState(() {
          _clients = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.people_outline, color: Color(0xFF1F4E79)),
          SizedBox(width: 8),
          Text('Asignar Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Buscar por nombre o identificador...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadClients();
                  },
                )
              ),
              onChanged: (val) => _loadClients(val),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _clients.isEmpty
                      ? const Center(child: Text('No se encontraron clientes.'))
                      : ListView.separated(
                          itemCount: _clients.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = _clients[index];
                            final isPublicoGral = c.id == 'PUBLICO-GRAL';
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isPublicoGral ? Colors.grey.shade200 : const Color(0xFFE3F2FD),
                                child: Icon(isPublicoGral ? Icons.storefront : Icons.person, 
                                  color: isPublicoGral ? Colors.grey.shade700 : const Color(0xFF1F4E79)),
                              ),
                              title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: isPublicoGral 
                                ? const Text('Venta estándar sin crédito')
                                : Text('Deuda activa: \$${c.saldoDeudor.toStringAsFixed(2)}', 
                                    style: TextStyle(color: c.saldoDeudor > 0 ? Colors.red.shade700 : Colors.green)),
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
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}