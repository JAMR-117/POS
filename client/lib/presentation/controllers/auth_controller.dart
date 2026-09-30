import 'package:flutter/foundation.dart';
import '../../data/repositories/user_repository.dart';

class AuthController extends ChangeNotifier {
  final UserRepository _userRepository;

  AuthController({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.rol == 'admin';
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String pin) async {
    _setLoading(true);
    try {
      final user = await _userRepository.authenticateWithPin(pin);
      if (user != null) {
        _currentUser = user;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'PIN incorrecto o usuario inactivo';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error de validación: $e';
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void logout() {
    _currentUser = null;
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}