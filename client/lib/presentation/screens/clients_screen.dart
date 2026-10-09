import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/repositories/client_repository.dart';
import '../controllers/shift_controller.dart';

class ClientsScreen extends StatefulWidget {
  final ShiftController shiftController;

  const ClientsScreen({super.key, required this.shiftController});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final ClientRepository _repo = ClientRepository();
  List<ClientModel> _clients = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients([String query = '']) async {
    setState(() => _isLoading = true);
    final results = await _repo.getClients(query);
    if (mounted) {
      setState(() {
        _clients = results;
        _isLoading = false;
      });
    }
  }

  void _showAbonoDialog(ClientModel client) {
    final TextEditingController montoController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text('Abonar a ${client.nombre}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Deuda Actual: \$${client.saldoDeudor.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 16),
                TextField(
                  controller: montoController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                  decoration: const InputDecoration(
                    labelText: 'Monto a recibir (\$)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
                onPressed: isProcessing ? null : () async {
                  final monto = double.tryParse(montoController.text) ?? 0.0;
                  if (monto <= 0) return;

                  setModalState(() => isProcessing = true);
                  try {
                    await _repo.registrarAbono(
                      clienteId: client.id,
                      monto: monto,
                      corteCajaId: widget.shiftController.activeShiftId,
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      _loadClients(); // Refrescar la lista
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Abono registrado exitosamente.'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    setModalState(() => isProcessing = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                },
                child: isProcessing 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('REGISTRAR ABONO'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Directorio y Cuentas por Cobrar'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar cliente...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => _loadClients(val),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _clients.length,
                    itemBuilder: (context, index) {
                      final c = _clients[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(c.telefono ?? 'Sin teléfono registrado'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${c.saldoDeudor.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: c.saldoDeudor > 0 ? Colors.red : Colors.green,
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (c.saldoDeudor > 0)
                              ElevatedButton(
                                onPressed: () => _showAbonoDialog(c),
                                child: const Text('ABONAR'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}