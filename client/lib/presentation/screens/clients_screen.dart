import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/local/business_config.dart';
import '../../data/local/models.dart';
import '../../data/repositories/client_repository.dart';
import '../controllers/shift_controller.dart';

class ClientsScreen extends StatefulWidget {
  final ShiftController shiftController;
  final bool showAppBar;

  const ClientsScreen({
    super.key,
    required this.shiftController,
    this.showAppBar = true,
  });

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final ClientRepository _repo = ClientRepository();
  List<Cliente> _clients = [];
  Cliente? _selectedClient;
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
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            title: Text(isEditing ? 'Editar Cliente' : 'Nuevo Cliente / Cerrajero'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
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
                    if (BusinessConfig.current.creditoClientesHabilitado) ...[
                      TextField(
                        controller: limitCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Límite de Crédito Autorizado (\$)', border: OutlineInputBorder()),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Color(0xFF795548)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Crédito deshabilitado globalmente en Configuración.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF795548)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
    final movements = await _repo.getClientAccountHistory(client.id);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ClientAccountStatementDialog(
        client: client,
        initialMovements: movements,
        onRegistrarAbono: () {
          Navigator.pop(ctx);
          _showAbonoDialog(client);
        },
      ),
    );
  }

  void _showAbonoDialog(Cliente client) {
    if (client.saldoDeudor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('El cliente "${client.nombre}" no tiene saldo deudor pendiente.')),
      );
      return;
    }
    final TextEditingController montoController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentMonto = double.tryParse(montoController.text) ?? 0.0;
          String? validationError;
          if (montoController.text.trim().isNotEmpty) {
            if (currentMonto <= 0) {
              validationError = 'El abono debe ser mayor a \$0.00';
            } else if (currentMonto > client.saldoDeudor + 0.001) {
              validationError = 'El abono no puede superar la deuda actual de \$${client.saldoDeudor.toStringAsFixed(2)}';
            }
          }

          final bool canConfirm = currentMonto > 0 && currentMonto <= client.saldoDeudor + 0.001 && !isProcessing;

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            title: Row(
              children: [
                const Icon(Icons.payment, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Expanded(child: Text('Abonar a cuenta: ${client.nombre}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Deuda actual:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                        Text('\$${client.saldoDeudor.toStringAsFixed(2)}', 
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1F4E79),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text('Liquidar total (\$${client.saldoDeudor.toStringAsFixed(2)})', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        setModalState(() {
                          montoController.text = client.saldoDeudor.toStringAsFixed(2);
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: montoController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                    decoration: InputDecoration(
                      labelText: 'Monto a recibir (\$)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.attach_money),
                      errorText: validationError,
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canConfirm ? const Color(0xFF2E7D32) : Colors.grey,
                  foregroundColor: Colors.white,
                ),
                icon: isProcessing 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('REGISTRAR ABONO'),
                onPressed: canConfirm ? () async {
                  final monto = double.tryParse(montoController.text) ?? 0.0;
                  if (monto <= 0 || monto > client.saldoDeudor + 0.001) return;

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
                } : null,
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteClient(Cliente client) {
    if (client.id == 'PUBLICO-GRAL') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se puede eliminar el cliente Público en General.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cliente'),
        content: Text('¿Está seguro de eliminar al cliente "${client.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await _repo.deleteClient(client.id);
              if (mounted) {
                nav.pop();
                setState(() => _selectedClient = null);
                _loadClients(_currentQuery);
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
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
            )
          : null,
      body: Column(
        children: [
          // Sub-barra interna estilo Eleventa (Clientes.png)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F4E79),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Estado de Cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (_selectedClient != null) {
                        _showStatementDialog(_selectedClient!);
                      } else if (_clients.isNotEmpty) {
                        _showStatementDialog(_clients.first);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seleccione un cliente primero.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Nuevo Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _showClientFormDialog(),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F4E79),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Modificar Cliente'),
                    onPressed: () {
                      if (_selectedClient != null) {
                        _showClientFormDialog(_selectedClient);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seleccione un cliente para modificar.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar Cliente'),
                    onPressed: () {
                      if (_selectedClient != null) {
                        _confirmDeleteClient(_selectedClient!);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Seleccione un cliente para eliminar.')),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.summarize_outlined, size: 18),
                    label: const Text('Reporte de Saldos (Solo Deudores)'),
                    selected: _soloDeudores,
                    onSelected: (val) {
                      setState(() => _soloDeudores = val);
                      _loadClients(_currentQuery);
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
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
                          final isSelected = _selectedClient?.id == c.id;
                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: const Color(0xFFE3F2FD),
                            onTap: () => setState(() => _selectedClient = c),
                            leading: CircleAvatar(
                              backgroundColor: hasDebt ? Colors.red.shade100 : const Color(0xFF1F4E79).withValues(alpha: 0.1),
                              child: Icon(Icons.person, color: hasDebt ? Colors.red.shade800 : const Color(0xFF1F4E79)),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    c.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
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
                                  tooltip: 'Estado de Cuenta / Historial',
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

enum _StatementFilter { todos, credito, contado, abonos, cancelados }

class _ClientAccountStatementDialog extends StatefulWidget {
  final Cliente client;
  final List<ClientMovementItem> initialMovements;
  final VoidCallback onRegistrarAbono;

  const _ClientAccountStatementDialog({
    required this.client,
    required this.initialMovements,
    required this.onRegistrarAbono,
  });

  @override
  State<_ClientAccountStatementDialog> createState() => _ClientAccountStatementDialogState();
}

class _ClientAccountStatementDialogState extends State<_ClientAccountStatementDialog> {
  _StatementFilter _filter = _StatementFilter.todos;

  List<ClientMovementItem> get _filteredMovements {
    switch (_filter) {
      case _StatementFilter.credito:
        return widget.initialMovements.where((m) => m.tipo == ClientMovementType.compraCredito).toList();
      case _StatementFilter.contado:
        return widget.initialMovements.where((m) => m.tipo == ClientMovementType.compraContado).toList();
      case _StatementFilter.abonos:
        return widget.initialMovements.where((m) => m.tipo == ClientMovementType.abonoPago).toList();
      case _StatementFilter.cancelados:
        return widget.initialMovements.where((m) => m.tipo == ClientMovementType.ticketCancelado).toList();
      case _StatementFilter.todos:
        return widget.initialMovements;
    }
  }

  void _showMovementDetail(BuildContext context, ClientMovementItem m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              m.tipo == ClientMovementType.ticketCancelado
                  ? Icons.cancel_outlined
                  : Icons.receipt_long,
              color: const Color(0xFF1F4E79),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Detalle de Venta: ${m.folio ?? m.id}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Fecha: ${m.fecha.toString().substring(0, 19)}', style: const TextStyle(fontSize: 12)),
                    Text('Pago: ${m.formaPago ?? "N/A"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Partidas cobradas en este ticket:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Flexible(
                child: m.partidas.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text('Sin detalle desglosado disponible')),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: m.partidas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final p = m.partidas[idx];
                            final cant = (p['cantidad'] as num?)?.toDouble() ?? 1.0;
                            final precio = (p['precio_historico'] as num?)?.toDouble() ?? 0.0;
                            final total = (p['total_linea'] as num?)?.toDouble() ?? (cant * precio);
                            final nom = p['nombre']?.toString() ?? p['producto_id']?.toString() ?? 'Producto';
                            final insumoId = p['insumo_utilizado_id']?.toString();
                            final cantInsumo = (p['cantidad_insumo_consumida'] as num?)?.toDouble() ?? 0.0;

                            return ListTile(
                              dense: true,
                              title: Text(nom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: insumoId != null && insumoId.isNotEmpty
                                  ? Text('🔧 Insumo ocupado: ${cantInsumo.toStringAsFixed(1)}x $insumoId', style: TextStyle(color: Colors.blue.shade900, fontSize: 11))
                                  : null,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('${cant.toStringAsFixed(cant % 1 == 0 ? 0 : 2)} x \$${precio.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Total del Ticket: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    '\$${m.monto.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: m.tipo == ClientMovementType.ticketCancelado ? Colors.red : const Color(0xFF1F4E79),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final double totalComprado = widget.initialMovements
        .where((m) => m.tipo == ClientMovementType.compraContado || m.tipo == ClientMovementType.compraCredito)
        .fold(0.0, (acc, m) => acc + m.monto);

    final double totalAbonado = widget.initialMovements
        .where((m) => m.tipo == ClientMovementType.abonoPago)
        .fold(0.0, (acc, m) => acc + m.monto);

    final int countCredito = widget.initialMovements.where((m) => m.tipo == ClientMovementType.compraCredito).length;
    final int countContado = widget.initialMovements.where((m) => m.tipo == ClientMovementType.compraContado).length;
    final int countAbonos = widget.initialMovements.where((m) => m.tipo == ClientMovementType.abonoPago).length;
    final int countCancelados = widget.initialMovements.where((m) => m.tipo == ClientMovementType.ticketCancelado).length;

    final movementsToShow = _filteredMovements;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1F4E79).withValues(alpha: 0.1),
                    child: const Icon(Icons.person, color: Color(0xFF1F4E79)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.client.nombre,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                        ),
                        Text(
                          'RFC: ${widget.client.rfcODni ?? "Sin RFC"} | Tel: ${widget.client.telefono ?? "Sin teléfono"} | Tarifa: ${widget.client.tarifaPreferencial}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Registrar Abono', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: widget.client.saldoDeudor > 0 ? widget.onRegistrarAbono : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4 Tarjetas Métricas de Resumen
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Límite de Crédito',
                      value: '\$${widget.client.limiteCredito.toStringAsFixed(2)}',
                      icon: Icons.credit_card,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Saldo Deudor Actual',
                      value: '\$${widget.client.saldoDeudor.toStringAsFixed(2)}',
                      icon: Icons.account_balance_wallet,
                      color: widget.client.saldoDeudor > 0 ? Colors.red.shade700 : Colors.green.shade700,
                      isHighlighted: widget.client.saldoDeudor > 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Total Comprado',
                      value: '\$${totalComprado.toStringAsFixed(2)}',
                      icon: Icons.shopping_bag_outlined,
                      color: const Color(0xFF1F4E79),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      title: 'Total Abonado',
                      value: '\$${totalAbonado.toStringAsFixed(2)}',
                      icon: Icons.payments_outlined,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Barra de Filtros Rápidos
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Todos (${widget.initialMovements.length})'),
                    selected: _filter == _StatementFilter.todos,
                    onSelected: (val) {
                      if (val) setState(() => _filter = _StatementFilter.todos);
                    },
                  ),
                  ChoiceChip(
                    label: Text('Compras a Crédito ($countCredito)'),
                    selected: _filter == _StatementFilter.credito,
                    selectedColor: Colors.orange.shade100,
                    onSelected: (val) {
                      if (val) setState(() => _filter = _StatementFilter.credito);
                    },
                  ),
                  ChoiceChip(
                    label: Text('Compras de Contado ($countContado)'),
                    selected: _filter == _StatementFilter.contado,
                    selectedColor: Colors.blue.shade100,
                    onSelected: (val) {
                      if (val) setState(() => _filter = _StatementFilter.contado);
                    },
                  ),
                  ChoiceChip(
                    label: Text('Abonos / Pagos ($countAbonos)'),
                    selected: _filter == _StatementFilter.abonos,
                    selectedColor: Colors.green.shade100,
                    onSelected: (val) {
                      if (val) setState(() => _filter = _StatementFilter.abonos);
                    },
                  ),
                  if (countCancelados > 0)
                    ChoiceChip(
                      label: Text('Cancelados ($countCancelados)'),
                      selected: _filter == _StatementFilter.cancelados,
                      selectedColor: Colors.red.shade100,
                      onSelected: (val) {
                        if (val) setState(() => _filter = _StatementFilter.cancelados);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Tabla / Línea de Tiempo de Movimientos
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: movementsToShow.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay movimientos para el filtro seleccionado.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          itemCount: movementsToShow.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final m = movementsToShow[idx];
                            return _buildMovementRow(context, m);
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Pie con botón de cerrar
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar Estado de Cuenta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isHighlighted ? color.withValues(alpha: 0.4) : Colors.grey.shade200,
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementRow(BuildContext context, ClientMovementItem m) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (m.tipo) {
      case ClientMovementType.compraCredito:
        badgeColor = Colors.orange.shade800;
        badgeText = 'Crédito';
        badgeIcon = Icons.credit_score;
        break;
      case ClientMovementType.compraContado:
        badgeColor = const Color(0xFF1F4E79);
        badgeText = 'Contado';
        badgeIcon = Icons.point_of_sale;
        break;
      case ClientMovementType.abonoPago:
        badgeColor = const Color(0xFF2E7D32);
        badgeText = 'Abono';
        badgeIcon = Icons.payments;
        break;
      case ClientMovementType.ticketCancelado:
        badgeColor = Colors.red.shade700;
        badgeText = 'Cancelado';
        badgeIcon = Icons.cancel;
        break;
    }

    // Resumen de partidas
    String resumenPartidas = '';
    if (m.tipo == ClientMovementType.abonoPago) {
      resumenPartidas = 'Abono a cuenta | Turno: ${m.corteCajaId ?? "Caja"}';
    } else if (m.partidas.isNotEmpty) {
      final names = m.partidas
          .take(3)
          .map((p) => '${(p["cantidad"] as num?)?.toDouble().toStringAsFixed(0) ?? "1"}x ${p["nombre"] ?? p["producto_id"]}')
          .join(', ');
      resumenPartidas = '${m.partidas.length} partidas: $names${m.partidas.length > 3 ? "..." : ""}';
    } else {
      resumenPartidas = m.concepto;
    }

    final String fechaStr = m.fecha.toString().length >= 16 ? m.fecha.toString().substring(0, 16) : m.fecha.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // Fecha y Hora
          SizedBox(
            width: 125,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fechaStr.split(' ').first, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(
                  fechaStr.contains(' ') ? fechaStr.split(' ').last : '',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Folio
          SizedBox(
            width: 100,
            child: Text(
              m.folio ?? 'S/F',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Tipo Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(badgeIcon, size: 12, color: badgeColor),
                const SizedBox(width: 4),
                Text(
                  badgeText,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Concepto / Artículos
          Expanded(
            child: Text(
              resumenPartidas,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),

          // Monto
          SizedBox(
            width: 100,
            child: Text(
              m.tipo == ClientMovementType.abonoPago
                  ? '-\$${m.monto.toStringAsFixed(2)}'
                  : '+\$${m.monto.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                decoration: m.tipo == ClientMovementType.ticketCancelado ? TextDecoration.lineThrough : null,
                color: m.tipo == ClientMovementType.abonoPago
                    ? const Color(0xFF2E7D32)
                    : (m.tipo == ClientMovementType.ticketCancelado ? Colors.red : const Color(0xFF1F4E79)),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Botón Ver Detalle
          if (m.partidas.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.search, size: 14),
              label: const Text('Detalle', style: TextStyle(fontSize: 11)),
              onPressed: () => _showMovementDetail(context, m),
            )
          else
            const SizedBox(width: 78),
        ],
      ),
    );
  }
}
