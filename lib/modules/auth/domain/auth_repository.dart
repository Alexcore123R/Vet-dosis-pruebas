import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'clinic_membership.dart';

abstract interface class AuthRepository {
  String? get userId;
  Stream<void> get changes;
  Future<void> signIn(String email, String password);
  Future<void> register(String email, String password);
  Future<void> googleSignIn();
  Future<void> signOut();
  Future<List<ClinicMembership>> memberships();
  Future<void> createClinic(String name);
  Future<void> joinClinic(String token);
  Future<String> invite(String clinicId, String email, ClinicRole role);
}

abstract interface class PersonalWorkspaceRepository {
  Future<void> createPersonalWorkspace();
}

abstract interface class PasswordRecoveryRepository {
  bool get recoveringPassword;
  Future<void> requestPasswordRecovery(String email);
  Future<void> completePasswordRecovery(String password);
}

abstract interface class TeamRepository {
  bool get teamManagementAvailable;
  /// null means the explicit capability endpoint is not installed yet.
  Future<bool?> canManageWorkspace(String clinicId);
  Future<Map<String, dynamic>> team(String clinicId);
  Future<void> setMemberRole(String clinicId, String userId, ClinicRole role);
  Future<void> removeMember(String clinicId, String userId);
  Future<void> revokeInvitation(String invitationId);
}

/// Documento público, ya publicado, mostrado antes de solicitar una cuenta.
/// No representa por sí solo un recibo de aceptación autenticado.
class RegistrationLegalDocument {
  const RegistrationLegalDocument({
    required this.version,
    required this.hash,
    required this.content,
  });

  final String version;
  final String hash;
  final String content;

  factory RegistrationLegalDocument.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Falta el documento legal publicado.');
    }
    final map = Map<String, dynamic>.from(value);
    final version = map['version'];
    final hash = map['hash'];
    final content = map['content'];
    if (version is! String ||
        version.trim().isEmpty ||
        hash is! String ||
        !RegExp(r'^[0-9a-f]{64}
      throw const FormatException('Documento legal publicado inválido.');
    }
    return RegistrationLegalDocument(
      version: version,
      hash: hash,
      content: content,
    );
  }
}

class RegistrationLegal {
  const RegistrationLegal({required this.terms, required this.privacy});
  final RegistrationLegalDocument terms;
  final RegistrationLegalDocument privacy;

  factory RegistrationLegal.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('No hay documentos legales publicados.');
    }
    final map = Map<String, dynamic>.from(value);
    return RegistrationLegal(
      terms: RegistrationLegalDocument.fromJson(map['terms']),
      privacy: RegistrationLegalDocument.fromJson(map['privacy']),
    );
  }

  bool sameVersions(RegistrationLegal other) =>
      terms.version == other.terms.version &&
      terms.hash == other.terms.hash &&
      privacy.version == other.privacy.version &&
      privacy.hash == other.privacy.hash;
}

/// Lectura anónima exclusiva de versiones vigentes; nunca devuelve borradores.
abstract interface class RegistrationLegalRepository {
  Future<RegistrationLegal?> registrationLegal();
}
).hasMatch(hash) ||
        content is! String ||
        content.trim().isEmpty ||
        sha256.convert(utf8.encode(content)).toString() != hash) {
      throw const FormatException('Documento legal publicado inválido.');
    }
    return RegistrationLegalDocument(
      version: version,
      hash: hash,
      content: content,
    );
  }
}

class RegistrationLegal {
  const RegistrationLegal({required this.terms, required this.privacy});
  final RegistrationLegalDocument terms;
  final RegistrationLegalDocument privacy;

  factory RegistrationLegal.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('No hay documentos legales publicados.');
    }
    final map = Map<String, dynamic>.from(value);
    return RegistrationLegal(
      terms: RegistrationLegalDocument.fromJson(map['terms']),
      privacy: RegistrationLegalDocument.fromJson(map['privacy']),
    );
  }

  bool sameVersions(RegistrationLegal other) =>
      terms.version == other.terms.version &&
      terms.hash == other.terms.hash &&
      privacy.version == other.privacy.version &&
      privacy.hash == other.privacy.hash;
}

/// Lectura anónima exclusiva de versiones vigentes; nunca devuelve borradores.
abstract interface class RegistrationLegalRepository {
  Future<RegistrationLegal?> registrationLegal();
}
