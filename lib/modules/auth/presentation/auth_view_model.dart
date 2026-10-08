import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/auth_repository.dart';
import '../domain/clinic_membership.dart';
import '../../offline/domain/offline_models.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel(
    this.repository, {
    this.googleEnabled = false,
    this.cache,
    this.syncStore,
    this.refreshInterval,
    this.onVerifiedAccess,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final AccessCache? cache;
  final SyncStore? syncStore;
  final Duration? refreshInterval;
  final Future<void> Function(List<ClinicMembership>)? onVerifiedAccess;
  final DateTime Function() now;
  Timer? _refreshTimer;
  String? _lastUserId;
  bool offline = false;
  final bool googleEnabled;
  final AuthRepository repository;
  StreamSubscription<void>? _subscription;
  List<ClinicMembership> memberships = [];
  ClinicMembership? active;
  bool busy = false;
  bool loadingMemberships = true;
  String? error;
  String? message;
  String? invitation;
  bool _disposed = false;
  int _revision = 0;
  bool get signedIn => repository.userId != null;
  Future<void> start() async {
    _subscription = repository.changes.listen((_) => refresh());
    await refresh();
    if (refreshInterval != null) {
      _refreshTimer = Timer.periodic(refreshInterval!, (_) {
        if (signedIn && !busy && !loadingMemberships) refresh(background: true);
      });
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({bool background = false}) async {
    final revision = ++_revision;
    final userId = repository.userId;
    final previousUser = _lastUserId;
    _lastUserId = userId;
    final previousClinic = active?.clinicId;
    if (!background || userId != previousUser) {
      active = null;
      memberships = [];
      loadingMemberships = true;
    }
    invitation = null;
    error = null;
    _notify();
    try {
      if (previousUser != null && previousUser != userId) {
        await cache?.clearAccess(previousUser);
      }
      final result = await repository.memberships();
      if (_disposed || revision != _revision || userId != repository.userId) {
        return;
      }
      if (userId != null) {
        final snapshot = MembershipSnapshot(userId, result, now().toUtc());
        try {
          await cache?.writeAccess(snapshot);
        } catch (_) {
          message = 'No se pudo guardar el acceso para usarlo sin conexión.';
        }
      }
      if (_disposed || revision != _revision || userId != repository.userId) {
        return;
      }
      offline = false;
      memberships = result;
      active =
          result.where((m) => m.clinicId == previousClinic).firstOrNull ??
          result.firstOrNull;
      try {
        await onVerifiedAccess?.call(result);
      } catch (_) {
        message =
            'La sincronización sigue pendiente. Tus cambios permanecen guardados.';
      }
    } on NetworkUnavailable {
      if (_disposed || revision != _revision || userId != repository.userId) {
        return;
      }
      MembershipSnapshot? snapshot;
      try {
        if (userId != null) snapshot = await cache?.readAccess(userId);
      } catch (_) {}
      if (_disposed || revision != _revision || userId != repository.userId) {
        return;
      }
      if (snapshot != null &&
          snapshot.userId == userId &&
          snapshot.validAt(now(), const Duration(hours: 24))) {
        memberships = snapshot.members;
        active =
            memberships
                .where((m) => m.clinicId == previousClinic)
                .firstOrNull ??
            memberships.firstOrNull;
        offline = true;
      } else {
        active = null;
        memberships = [];
        error =
            'Conéctate para verificar tu acceso. No hay una membresía guardada vigente.';
      }
    } catch (_) {
      if (_disposed || revision != _revision || userId != repository.userId) {
        return;
      }
      active = null;
      memberships = [];
      if (userId != null) {
        try {
          await cache?.clearAccess(userId);
        } catch (_) {}
      }
      error =
          'No se pudo verificar tu acceso. Revisa la conexión e intenta de nuevo.';
    }
    if (_disposed || revision != _revision) return;
    loadingMemberships = false;
    _notify();
  }

  void selectClinic(ClinicMembership membership) {
    if (!memberships.contains(membership)) return;
    active = membership;
    invitation = null;
    _notify();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool requireOnline = true,
  }) async {
    if (requireOnline && offline) {
      error = 'Conéctate para gestionar cuentas, clínicas o invitaciones.';
      _notify();
      return;
    }
    if (busy) return;
    busy = true;
    error = null;
    message = null;
    invitation = null;
    _notify();
    try {
      await action();
    } on PendingChanges {
      error =
          'Hay cambios pendientes de sincronizar o revisar. Conéctate antes de cerrar sesión.';
    } catch (_) {
      error =
          'No se pudo completar la operación. Verifica los datos y la conexión.';
    } finally {
      busy = false;
      _notify();
    }
  }

  bool get recoveryAvailable => repository is PasswordRecoveryRepository;
  bool get recoveringPassword =>
      recoveryAvailable &&
      (repository as PasswordRecoveryRepository).recoveringPassword;
  Future<void> requestPasswordRecovery(String email) => _run(() async {
    if (!recoveryAvailable ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw const FormatException('invalid_email');
    }
    await (repository as PasswordRecoveryRepository).requestPasswordRecovery(
      email.trim(),
    );
    message =
        'Si existe una cuenta con ese correo, recibirás un enlace para cambiar la contraseña.';
  });
  Future<void> completePasswordRecovery(String password) => _run(() async {
    if (!recoveringPassword || password.length < 8) {
      throw const FormatException('invalid_recovery');
    }
    await (repository as PasswordRecoveryRepository).completePasswordRecovery(
      password,
    );
    await refresh();
    message = 'Contraseña actualizada.';
  });

  Future<void> signIn(String email, String password) => _run(() async {
    await repository.signIn(email, password);
    await refresh();
  });
  Future<void> register(String email, String password) => _run(() async {
    await repository.register(email, password);
    message = 'Revisa tu correo para confirmar la cuenta antes de ingresar.';
  });
  Future<void> googleSignIn() => _run(repository.googleSignIn);
  bool get personalAvailable => repository is PersonalWorkspaceRepository;
  Future<void> createPersonalWorkspace() => _run(() async {
    await (repository as PersonalWorkspaceRepository).createPersonalWorkspace();
    await refresh();
    active = memberships.where((m) => m.isPersonal).firstOrNull ?? active;
    _notify();
  });
  Future<void> createClinic(String name) => _run(() async {
    await repository.createClinic(name);
    await refresh();
  });
  Future<void> joinClinic(String token) => _run(() async {
    await repository.joinClinic(token);
    await refresh();
  });
  Future<void> invite(String email, ClinicRole role) => _run(() async {
    final member = active;
    if (member == null || member.role != ClinicRole.admin) {
      throw StateError('admin_required');
    }
    final revision = _revision;
    final code = await repository.invite(member.clinicId, email, role);
    if (!_disposed && revision == _revision && active == member) {
      invitation = code;
    }
  });
  Future<void> signOut() => _run(() async {
    final userId = repository.userId;
    if (userId != null && (await syncStore?.pendingForUser(userId) ?? 0) > 0) {
      throw const PendingChanges();
    }
    try {
      await repository.signOut();
    } catch (_) {
      if (repository.userId != null) rethrow;
    }
    if (userId != null) {
      await cache?.clearAccess(userId);
      await syncStore?.purgeUser(userId);
    }
    await refresh();
  }, requireOnline: false);
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
