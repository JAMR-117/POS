import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/models.dart';
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
  List<Cliente> _clients = [];
  bool _isLoading = true;
  bool _soloDeudores = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients([String query = '']) async {
    setState(() => _isLoading = true);
    _currentQuery = query;
    final results = await _repo.getClients(query);
    if (mounted) {
      setState(() {
        _clients = _soloDeudores
            ? results.where((c) => c.saldoDeudor > 0).toList()
            : results;
        _isLoading = false;
      });
    }
  }

  void _showClientFormDialog([Cliente? clientToEdit]) {
    final bool isEditing = clientToEdit != null;
    final nombreCtrl = TextEditingController(text: clientToEdit?.nombre ?? '');
    final rfcCtrl = TextEditingController(text: clientToEdit?.rfcODni ?? '');
    final regimenCtrl = TextEditingController(text: clientToEdit?.regimenFiscal ?? '612 - Personas Físicas');
    final usoCfdiCtrl = TextEditingController(text: clientToEdit?.usoCfdi ?? 'G03 - Gastos en general');
    final cpCtrl = TextEditingController(text: clientToEdit?.codigoPostal ?? '');
    final emailCtrl = TextEditingController(text: clientToEdit?.correo ?? '');
    final phoneCtrl = TextEditingController(text: clientToEdit?.telefono ?? '');
    final addressCtrl = TextEditingController(text: clientToEdit?.direccion ?? '');
    final limitCtrl = TextEditingController(text: clientToEdit?.limiteCredito.toString() ?? '0.0');
    String tarifaSeleccionada = clientToEdit?.tarifaPreferencial ?? 'Público';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente / Cerrajero'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre / Razón Social *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: tarifaSeleccionada,
                            decoration: const InputDecoration(labelText: 'Tarifa Asignada', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'Público', child: Text('Precio Público')),
                              DropdownMenuItem(value: 'Cerrajero', child: Text('Colega Cerrajero')),
                              DropdownMenuItem(value: 'Taller', child: Text('Taller Automotriz')),
                              DropdownMenuItem(value: 'Mayoreo', child: Text('Mayoreo')),
                            ],
                            onChanged: (val) {
                              if (val != null) setModalState(() => tarifaSeleccionada = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rfcCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(labelText: 'RFC o DNI Fiscal', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: cpCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Código Postal Fiscal', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Correo Electrónico (Facturación)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: regimenCtrl,
                      decoration: const InputDecoration(labelText: 'Régimen Fiscal (SAT)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usoCfdiCtrl,
                      decoration: const InputDecoration(labelText: 'Uso de CFDI', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Dirección Completa', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: limitCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Límite de Crédito Autorizado (\$)', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
                onPressed: () async {
                  final name = nombreCtrl.text.trim();
                  if (name.isEmpty) return;

                  final client = Cliente(
                    id: clientToEdit?.id ?? 'CLI_${DateTime.now().microsecondsSinceEpoch}',
                    nombre: name,
                    telefono: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    rfcODni: rfcCtrl.text.trim().isEmpty ? null : rfcCtrl.text.trim(),
                    regimenFiscal: regimenCtrl.text.trim().isEmpty ? null : regimenCtrl.text.trim(),
                    usoCfdi: usoCfdiCtrl.text.trim().isEmpty ? null : usoCfdiCtrl.text.trim(),
                    codigoPostal: cpCtrl.text.trim().isEmpty ? null : cpCtrl.text.trim(),
                    correo: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    direccion: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                    limiteCredito: double.tryParse(limitCtrl.text) ?? 0.0,
                    saldoDeudor: clientToEdit?.saldoDeudor ?? 0.0,
                    tarifaPreferencial: tarifaSeleccionada,
                    activo: true,
                  );

                  await _repo.saveClient(client);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    _loadClients(_currentQuery);
                  }
                },
                child: const Text('Guardar Cliente'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStatementDialog(Cliente client) async {
    final abonos = await _repo.getClientAbonos(client.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: Color(0xFF1F4E79)),
            const SizedBox(width: 8),
            Expanded(child: Text('Estado de Cuenta: ${client.nombre}')),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 350,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: client.saldoDeudor > 0 ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Saldo Deudor Actual:', style: TextStyle(fontWeight: FontWeight.bold, color: client.saldoDeudor > 0 ? Colors.red.shade900 : Colors.green.shade900)),
                    Text('\$${client.saldoDeudor.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: client.saldoDeudor > 0 ? Colors.red.shade900 : Colors.green.shade900)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Historial de Abonos Registrados:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Expanded(
                child: abonos.isEmpty
                    ? const Center(child: Text('No hay abonos registrados para este cliente.', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        itemCount: abonos.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final a = abonos[idx];
                          final monto = (a['monto'] as num).toDouble();
                          final fecha = a['fecha'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                            title: Text('Abono: \$${monto.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Fecha: $fecha | Turno: ${a['corte_caja_id']}'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (client.saldoDeudor > 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                _showAbonoDialog(client);
              },
              child: const Text('Registrar Abono'),
            ),
        ],
      ),
    );
  }

  void _showAbonoDialog(Cliente client) {
    final TextEditingController montoController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text('Abonar a cuenta de ${client.nombre}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Deuda Pendiente: \$${client.saldoDeudor.toStringAsFixed(2)}', 
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
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(ctx);
                  try {
                    await _repo.registrarAbono(
                      clienteId: client.id,
                      monto: monto,
                      corteCajaId: widget.shiftController.activeShiftId,
                    );
                    if (mounted) {
                      navigator.pop();
                      _loadClients(_currentQuery);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Abono registrado exitosamente e ingresado a caja.'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setModalState(() => isProcessing = false);
                      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: isProcessing 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('REGISTRAR ABONO'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes y Cuentas por Cobrar'),
        backgroundColor: const Color(0xFF1F4E79),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Nuevo Cliente',
            onPressed: () => _showClientFormDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por Nombre, Teléfono o RFC...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => _loadClients(val),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Solo con Saldo Deudor'),
                  selected: _soloDeudores,
                  onSelected: (val) {
                    setState(() => _soloDeudores = val);
                    _loadClients(_currentQuery);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _clients.isEmpty
                    ? const Center(child: Text('No hay clientes registrados o coincidentes.'))
                    : ListView.separated(
                        itemCount: _clients.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = _clients[index];
                          final hasDebt = c.saldoDeudor > 0;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: hasDebt ? Colors.red.shade100 : const Color(0xFF1F4E79).withValues(alpha: 0.1),
                              child: Icon(Icons.person, color: hasDebt ? Colors.red.shade800 : const Color(0xFF1F4E79)),
                            ),
                            title: Row(
                              children: [
                                Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    c.tarifaPreferencial,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text('Tel: ${c.telefono ?? "Sin teléfono"} | RFC: ${c.rfcODni ?? "Sin RFC"}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${c.saldoDeudor.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
                                      ),
                                    ),
                                    Text(
                                      hasDebt ? 'Deuda activa' : 'Al corriente',
                                      style: TextStyle(fontSize: 10, color: hasDebt ? Colors.red : Colors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.receipt_long, color: Color(0xFF1F4E79)),
                                  tooltip: 'Estado de Cuenta',
                                  onPressed: () => _showStatementDialog(c),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.grey),
                                  tooltip: 'Editar Datos',
                                  onPressed: () => _showClientFormDialog(c),
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