import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'backup_archive.dart';

/// Passwords and derived keys are used in memory only; never persisted by this class.
class BackupCipher {
  static const iterations = 600000;
  static const maxEncryptedBytes = 72 * 1024 * 1024;
  static final _aad = utf8.encode('VetDosis Pro encrypted archive v1');
  static final _algorithm = AesGcm.with256bits();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );

  static Map<String, dynamic> _envelope(Uint8List bytes) {
    if (bytes.length > maxEncryptedBytes) {
      throw const FormatException('El archivo supera el límite de 72 MB.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Archivo de respaldo inválido.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Archivo de respaldo inválido.');
    }
  }

  static bool isEncrypted(Uint8List bytes) =>
      _envelope(bytes)['format'] == 'vetdosis-encrypted-archive';

  static Future<SecretKey> _key(String password, List<int> salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  static Future<Uint8List> encrypt(Uint8List archive, String password) async {
    if (password.trim().length < 12 || password.length > 1024) {
      throw const FormatException(
        'Usa una contraseña de entre 12 y 1024 caracteres.',
      );
    }
    BackupArchive.verify(archive);
    final salt = SecretKeyData.random(length: 16).bytes;
    final nonce = _algorithm.newNonce();
    final key = await _key(password, salt);
    final box = await _algorithm.encrypt(
      archive,
      secretKey: key,
      nonce: nonce,
      aad: _aad,
    );
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'vetdosis-encrypted-archive',
          'version': 1,
          'cipher': 'AES-256-GCM',
          'kdf': 'PBKDF2-HMAC-SHA256',
          'iterations': iterations,
          'salt': base64Encode(salt),
          'nonce': base64Encode(nonce),
          'ciphertext': base64Encode(box.cipherText),
          'mac': base64Encode(box.mac.bytes),
        }),
      ),
    );
    if (bytes.length > maxEncryptedBytes) {
      throw const FormatException(
        'El respaldo cifrado requiere exportación por lotes.',
      );
    }
    return bytes;
  }

  static Future<Uint8List> decrypt(Uint8List encrypted, String password) async {
    final e = _envelope(encrypted);
    if (e['format'] != 'vetdosis-encrypted-archive' ||
        e['version'] != 1 ||
        e['cipher'] != 'AES-256-GCM' ||
        e['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        e['iterations'] != iterations) {
      throw const FormatException('Formato de cifrado no compatible.');
    }
    if (password.isEmpty || password.length > 1024) {
      throw const FormatException('Ingresa la contraseña del respaldo.');
    }
    try {
      final salt = base64Decode(e['salt'] as String),
          nonce = base64Decode(e['nonce'] as String);
      final mac = base64Decode(e['mac'] as String),
          ciphertext = base64Decode(e['ciphertext'] as String);
      if (salt.length != 16 ||
          nonce.length != 12 ||
          mac.length != 16 ||
          ciphertext.length > BackupArchive.maxBytes) {
        throw const FormatException('Archivo cifrado inválido.');
      }
      final key = await _key(password, salt);
      final plaintext = Uint8List.fromList(
        await _algorithm.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
          aad: _aad,
        ),
      );
      BackupArchive.verify(plaintext);
      return plaintext;
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Contraseña incorrecta o archivo cifrado alterado.',
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('No se pudo abrir el archivo cifrado.');
    }
  }
}
