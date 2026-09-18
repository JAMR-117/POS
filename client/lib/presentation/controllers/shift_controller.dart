import 'package:flutter/foundation.dart';
import '../../data/repositories/shift_repository.dart';

class ShiftController extends ChangeNotifier {
  final ShiftRepository _shiftRepository;

  ShiftController({ShiftRepository? shiftRepository})
      : _shiftRepository = shiftRepository ?? ShiftRepository();

  ShiftRecord? _currentShift;
  ShiftSummary? _currentSummary;
  bool _isLoading = false;
  String? _errorMessage;

  ShiftRecord? get currentShift => _currentShift;
  ShiftSummary? get currentSummary => _currentSummary;
  bool get hasActiveShift => _currentShift != null && _currentShift!.estado == 'abierto';
  String get activeShiftId => _currentShift?.id ?? '';
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Verifica el turno activo al iniciar el sistema
  Future<void> checkActiveShift() async {
    _setLoading(true);
    try {
      _currentShift = await _shiftRepository.getActiveShift();
      if (_currentShift != null) {
        _currentSummary = await _shiftRepository.getShiftSummary(_currentShift!.id);
      } else {
        _currentSummary = null;
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Abre un nuevo turno de caja con fondo inicial
  Future<void> openShift({required String usuarioId, required double montoInicial}) async {
    _setLoading(true);
    try {
      _currentShift = await _shiftRepository.openShift(
        usuarioId: usuarioId,
        montoInicial: montoInicial,
      );
      _currentSummary = await _shiftRepository.getShiftSummary(_currentShift!.id);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Refresca las métricas agregadas del turno activo (Corte X)
  Future<ShiftSummary?> loadShiftSummary() async {
    if (!hasActiveShift) return null;
    try {
      _currentSummary = await _shiftRepository.generateCorteX(activeShiftId);
      notifyListeners();
      return _currentSummary;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Ejecuta el cierre contable Z del turno
  Future<void> closeShiftCorteZ(double efectivoDeclarado) async {
    if (!hasActiveShift) {
      throw Exception('No hay ningún turno abierto para cerrar.');
    }

    _setLoading(true);
    try {
      await _shiftRepository.closeShiftCorteZ(
        shiftId: activeShiftId,
        efectivoContado: efectivoDeclarado,
      );
      _currentShift = null;
      _currentSummary = null;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}