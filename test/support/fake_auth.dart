import 'dart:async';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';

const member = ClinicMembership(
  clinicId: 'a',
  clinicName: 'Clínica A',
  userId: 'user-a',
  role: ClinicRole.auxiliar,
);

class FakeAuth implements AuthRepository {
  @override
  String? userId = 'user-a';
  final controller = StreamController<void>.broadcast();
  List<ClinicMembership> rows = [member];
  bool failRead = false;
  int inviteCalls = 0;
  Completer<List<ClinicMembership>>? pending;
  @override
  Stream<void> get changes => controller.stream;
  @override
  Future<List<ClinicMembership>> memberships() async {
    if (failRead) throw StateError('offline');
    if (pending != null) return pending!.future;
    return userId == null ? [] : rows;
  }

  @override
  Future<void> signIn(String email, String password) async {
    userId = 'user-a';
  }

  @override
  Future<void> register(String email, String password) async {}
  @override
  Future<void> googleSignIn() async {}
  @override
  Future<void> signOut() async {
    userId = null;
  }

  @override
  Future<void> createClinic(String name) async {}
  @override
  Future<void> joinClinic(String token) async {}
  @override
  Future<String> invite(String clinicId, String email, ClinicRole role) async {
    inviteCalls++;
    return 'test-token';
  }
}
