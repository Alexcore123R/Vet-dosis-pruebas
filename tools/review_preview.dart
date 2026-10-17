// Local UI review target only. Uses synthetic repositories; never connects Supabase.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/ai/domain/ai_repository.dart';
import 'package:vetdosis_pro/modules/subscriptions/domain/subscription_repository.dart';
import '../test/support/fake_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final params = Uri.base.queryParameters;
  final role =
      ClinicRole.values.where((r) => r.name == params['role']).firstOrNull ??
      ClinicRole.admin;
  final fake = FakeAuth()
    ..rows = [
      ClinicMembership(
        clinicId: 'preview',
        clinicName: 'REVISIÓN LOCAL · Sin datos reales',
        userId: 'user-a',
        role: role,
      ),
    ];
  final auth = AuthViewModel(fake);
  await auth.start();
  final repo = SettingsRepository();
  final core = CoreViewModel(
    repo,
    AppSettings(
      palette: (int.tryParse(params['palette'] ?? '0') ?? 0).clamp(0, 4),
      brightness: params['theme'] ?? 'system',
    ),
  );
  core.navigate(params['screen'] ?? 'Inicio');
  runApp(
    VetDosisApp(
      model: core,
      auth: auth,
      ai: ReviewAi(),
      subscriptions: PlanFake(),
    ),
  );
}

class ReviewAi extends AiFake implements StarterAiRepository {
  @override
  Future<Map<String, dynamic>> starterStatus(String clinic) async => {
    'enabled': false,
    'provider': 'google',
    'model': 'gemini-2.5-flash',
    'limit': 5,
    'used': 0,
  };
  @override
  Future<String> starterHelp(
    String clinic,
    String topic,
    String operation,
  ) async => throw StateError('preview only');
}

class AiFake implements AiRepository {
  bool fail = false;
  Completer<Map<String, dynamic>>? delayed;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async {
    if (fail) throw StateError('denied');
    if (delayed != null) return delayed!.future;
    return {
      'chats': [
        {
          'id': 'chat',
          'owner_id': 'user-a',
          'title':
              'Conversación de ejemplo para revisar interfaz, sin datos reales',
          'visibility': 'private',
          'context_mode': 'none',
          'version': 1,
          'audience': [],
        },
      ],
      'connections': [],
      'daily_used': 0,
      'daily_limit': 5,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> messages(String chat) async => [
    {'role': 'user', 'body': 'Privado'},
  ];
  @override
  Future<String> create(String clinic, String title, String operation) async =>
      'chat';
  @override
  Future<void> policy(
    String chat,
    int version,
    String visibility,
    String context,
    List<String> audience,
  ) async {}
  @override
  Future<void> delete(String chat) async {}
  @override
  Future<void> abandon(String chat) async {}
  @override
  Future<void> saveKey(
    String provider,
    String scope,
    String clinic,
    String key,
  ) async {}
  @override
  Future<void> disableKey(String connection) async {}
  @override
  Future<void> rotateKey(String connection, String key) async {}
  @override
  Future<List<Map<String, dynamic>>> models(String connection) async => [];
  @override
  Future<void> send(
    String chat,
    String connection,
    String model,
    String message,
    String operation,
    bool personal,
    bool team,
  ) async {}
}

class PlanFake implements SubscriptionRepository {
  int requests = 0;
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async => {
    'workspace': {'kind': 'personal'},
    'effective': {
      'name': 'Gratis',
      'code': 'free',
      'patient_limit': 50,
      'storage_bytes': 262144000,
      'ai_daily': 5,
    },
    'patients': 0,
    'usage_bytes': '0',
    'reward_points': '0',
    'billing_enabled': false,
    'reward_enabled': false,
    'grants': [],
    'requests': [],
    'plans': [
      {
        'code': 'individual',
        'name': 'Individual',
        'monthly_cents': 19900,
        'annual_cents': 199000,
        'patient_limit': 5000,
        'storage_bytes': 2147483648,
        'ai_daily': 200,
        'team': false,
      },
    ],
  };
  @override
  Future<void> request(
    String clinic,
    String plan,
    String period,
    String operation,
  ) async {
    requests++;
  }

  @override
  Future<String> checkout(String request) async => throw StateError('disabled');
  @override
  Future<void> redeem(String clinic, String operation) async {}
}
