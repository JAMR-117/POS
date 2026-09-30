import 'package:flutter/material.dart';
import '../../data/repositories/user_repository.dart';
import '../controllers/auth_controller.dart';

class AdminAuthDialog extends StatefulWidget {
  final AuthController authController;

  const AdminAuthDialog({super.key, required this.authController});

  static Future<bool> requestAdminAccess(BuildContext context, AuthController auth) async {
    if (auth.isAdmin) return true; // Si ya es admin, pasa directo.

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminAuthDialog(authController: auth),
    );
    return result ?? false;
  }

  @override
  State<AdminAuthDialog> createState() => _AdminAuthDialogState();
}

class _AdminAuthDialogState extends State<AdminAuthDialog> {
  final TextEditingController _pinController = TextEditingController();
  final UserRepository _userRepo = UserRepository();
  bool _isLoading = false;
  String? _error;

  Future<void> _validatePin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = await _userRepo.authenticateWithPin(_pinController.text);
      if (user != null && user.rol == 'admin') {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _error = 'PIN incorrecto o usuario sin permisos de administrador.');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.security, color: Color(0xFFD32F2F)),
          SizedBox(width: 8),
          Text('Autorización Requerida'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Esta acción requiere permisos de Administrador. Ingrese el PIN de autorización:'),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          TextField(
            controller: _pinController,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (_) => _validatePin(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F4E79), foregroundColor: Colors.white),
          onPressed: _isLoading ? null : _validatePin,
          child: _isLoading 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Autorizar'),
        ),
      ],
    );
  }
}