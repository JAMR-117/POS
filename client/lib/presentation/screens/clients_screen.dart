import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/repositories/client_repository.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final ClientRepository _repository = ClientRepository();
  final TextEditingController _searchController = TextEditingController();
  List<ClientModel> _clients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoading = true);
    final results = await _repository.getClients(_searchController.text);
    setState(() {
      _clients = results;
      _isLoading = false;
    });
  }

  void _showAbonoDialog(ClientModel client) {
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Abonar a cuenta: ${client.nombre}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Deuda actual: \$${client.saldoDeudor.toStringAsFixed(2)}', 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto a abonar (\$)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
            onPressed: () async {
              final monto = double.tryParse(amountController.text) ?? 0;
              if (monto <= 0 || monto > client.saldoDeudor) return;
              
              await _repository.registrarAbono(
                abonoId: _generateLocalUUID(),
                clienteId: client.id,
                monto: monto,
              );
              if (mounted) {
                Navigator.pop(ctx);
                _loadClients(); // Refrescar lista
              }
            },
            child: const Text('Registrar Abono'),
          ),
        ],
      ),
    );
  }

  String _generateLocalUUID() {
    final random = Random.secure();
    return List.generate(16, (i) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Directorio de Clientes'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _loadClients(),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _clients.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final client = _clients[index];
                    final tieneDeuda = client.saldoDeudor > 0;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tieneDeuda ? Colors.red.shade100 : Colors.green.shade100,
                        child: Icon(Icons.person, color: tieneDeuda ? Colors.red : Colors.green),
                      ),
                      title: Text(client.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Límite: \$${client.limiteCredito.toStringAsFixed(2)} | Tel: ${client.telefono ?? 'N/A'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\$${client.saldoDeudor.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: tieneDeuda ? Colors.red : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 16
                            ),
                          ),
                          if (tieneDeuda) ...[
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: () => _showAbonoDialog(client),
                              child: const Text('Abonar'),
                            )
                          ]
                        ],
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}