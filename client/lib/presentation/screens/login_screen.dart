import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
// O la ruta a tu POS

class LoginScreen extends StatefulWidget {
  final AuthController authController;
  final Widget posAppTarget; // Widget de destino tras autenticar

  const LoginScreen({
    super.key,
    required this.authController,
    required this.posAppTarget,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  static const int _maxPinLength = 6;

  void _onNumPressed(String num) {
    if (_pin.length < _maxPinLength) {
      setState(() {
        _pin += num;
      });
      // Auto-submit si llega a 4 (puedes ajustar esta lógica según el largo de tus PINs)
      if (_pin.length == 4) {
        _handleLogin();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _handleLogin() async {
    if (_pin.isEmpty) return;

    final success = await widget.authController.login(_pin);
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.posAppTarget),
      );
    } else {
      setState(() => _pin = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.authController.errorMessage ?? 'Error de acceso'),
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Evita volver atrás mediante gestos o botón físico del SO
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1F4E79),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_person, size: 64, color: Color(0xFF1F4E79)),
                    const SizedBox(height: 16),
                    const Text('Sistema POS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text('Ingrese su PIN de acceso', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                    
                    // Indicadores visuales de PIN
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index < _pin.length ? const Color(0xFF1F4E79) : Colors.grey.shade300,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),

                    // Numpad Táctil
                    if (widget.authController.isLoading)
                      const CircularProgressIndicator()
                    else
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.2,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (int i = 1; i <= 9; i++) _buildNumBtn(i.toString()),
                          _buildActionBtn(Icons.backspace, _onDelete, Colors.red.shade100),
                          _buildNumBtn('0'),
                          _buildActionBtn(Icons.check_circle, _handleLogin, Colors.green.shade100),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumBtn(String text) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFECEFF1),
        foregroundColor: const Color(0xFF1F4E79),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _onNumPressed(text),
      child: Text(text, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionBtn(IconData icon, VoidCallback onPressed, Color bgColor) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: const Color(0xFF1F4E79),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      child: Icon(icon, size: 28),
    );
  }
}