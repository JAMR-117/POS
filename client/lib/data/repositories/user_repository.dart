import '../local/database_helper.dart';

class UserModel {
  final String id;
  final String nombre;
  final String pinAcceso;
  final String rol;
  final bool activo;

  UserModel({
    required this.id,
    required this.nombre,
    required this.pinAcceso,
    required this.rol,
    required this.activo,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      pinAcceso: map['pin_acceso'] as String,
      rol: map['rol'] as String,
      activo: (map['activo'] as int) == 1,
    );
  }
}

class UserRepository {
  final DatabaseHelper _dbHelper;

  UserRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Valida el inicio de sesión mediante un PIN numérico exacto
  Future<UserModel?> authenticateWithPin(String pin) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'usuarios',
      where: 'pin_acceso = ? AND activo = 1',
      whereArgs: [pin],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return UserModel.fromMap(results.first);
    }
    return null;
  }
}