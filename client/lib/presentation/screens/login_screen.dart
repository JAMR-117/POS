import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/string_utils.dart';
import '../../data/repositories/user_repository.dart';
import '../controllers/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  final AuthController authController;
  final VoidCallback? onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.authController,
    this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final UserRepository _userRepo = UserRepository();
  final FocusNode _keyboardFocusNode = FocusNode();
  String _pin = '';
  static const int _maxPinLength = 6;
  List<UserModel> _availableUsers = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _userRepo.getActiveUsers();
      if (mounted) {
        setState(() {
          _availableUsers = users;
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  void _onNumPressed(String num) {
    if (_pin.length < _maxPinLength) {
      setState(() {
        _pin += num;
      });
      if (_pin.length == 4) {
        _handleLogin();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.safeSub(0, _pin.length - 1);
      });
    }
  }

  Future<void> _handleLogin() async {
    if (_pin.isEmpty) return;

    final success = await widget.authController.login(_pin);
    if (success && mounted) {
      widget.onLoginSuccess?.call();
    } else {
      setState(() => _pin = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.authController.errorMessage ?? 'PIN incorrecto o cajero inactivo'),
            backgroundColor: const Color(0xFFD32F2F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
              _onNumPressed('0');
            } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
              _onNumPressed('1');
            } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
              _onNumPressed('2');
            } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
              _onNumPressed('3');
            } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
              _onNumPressed('4');
            } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
              _onNumPressed('5');
            } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
              _onNumPressed('6');
            } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
              _onNumPressed('7');
            } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
              _onNumPressed('8');
            } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
              _onNumPressed('9');
            } else if (key == LogicalKeyboardKey.backspace) {
              _onDelete();
            } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
              _handleLogin();
            }
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF1F4E79),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Encabezado
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F4E79).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_person, size: 52, color: Color(0xFF1F4E79)),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CARprog POS',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
                      ),
                      const Text(
                        'Sistema de Cerrajería y Punto de Venta',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 16),

                      // Lista de Usuarios Disponibles en DB
                      if (!_isLoadingUsers && _availableUsers.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: _availableUsers.map((u) {
                            final isAdmin = u.rol == 'admin';
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _pin = u.pinAcceso;
                                });
                                _handleLogin();
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isAdmin ? const Color(0xFFE3F2FD) : const Color(0xFFF1F8E9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isAdmin ? const Color(0xFF90CAF9) : const Color(0xFFA5D6A7),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isAdmin ? Icons.admin_panel_settings : Icons.person,
                                      size: 14,
                                      color: isAdmin ? const Color(0xFF0D47A1) : const Color(0xFF2E7D32),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      u.nombre,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isAdmin ? const Color(0xFF0D47A1) : const Color(0xFF2E7D32),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const Text('Ingrese su PIN de acceso (o use teclado físico)', style: TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 14),

                      // Indicadores visuales de PIN
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (index) {
                          final isFilled = index < _pin.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? const Color(0xFF1F4E79) : Colors.grey.shade300,
                              border: Border.all(
                                color: isFilled ? const Color(0xFF1F4E79) : Colors.grey.shade400,
                                width: 2,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),

                      // Numpad Táctil
                      if (widget.authController.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        )
                      else
                        GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.3,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (int i = 1; i <= 9; i++) _buildNumBtn(i.toString()),
                            _buildActionBtn(Icons.backspace, _onDelete, Colors.red.shade50, Colors.red.shade700),
                            _buildNumBtn('0'),
                            _buildActionBtn(Icons.check_circle, _handleLogin, Colors.green.shade50, const Color(0xFF2E7D32)),
                          ],
                        ),
                      const SizedBox(height: 14),

                      // Pista discreta para pruebas
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9C4),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFF59D)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Color(0xFFF57F17)),
                            SizedBox(width: 6),
                            Text(
                              'Pista: Admin [PIN: 1234]  |  Caja 1 [PIN: 5678]',
                              style: TextStyle(fontSize: 11, color: Color(0xFFF57F17), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumBtn(String num) {
    return Material(
      color: const Color(0xFFF5F7FA),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _onNumPressed(num),
        child: Center(
          child: Text(
            num,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F4E79)),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn(IconData icon, VoidCallback onTap, Color bgColor, Color iconColor) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }
}
