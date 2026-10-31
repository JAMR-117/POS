import 'dart:io' as io;

/// Native IO implementation for file reading operations
Future<String?> readLocalFile(String path) async {
  try {
    final file = io.File(path);
    if (await file.exists()) {
      return await file.readAsString();
    }
  } catch (_) {
    // Return null if file access is not permitted or fails
  }
  return null;
}
