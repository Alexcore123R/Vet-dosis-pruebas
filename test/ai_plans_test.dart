import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/ai/domain/ai_repository.dart';
import 'package:vetdosis_pro/modules/ai/presentation/ai_view_model.dart';
import 'package:vetdosis_pro/modules/ai/presentation/ai_screen.dart';
import 'package:vetdosis_pro/modules/subscriptions/domain/subscription_repository.dart';
import 'package:vetdosis_pro/modules/subscriptions/presentation/subscription_screen.dart';
import 'package:vetdosis_pro/modules/auth/domain/auth_repository.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'support/fake_auth.dart';

const personal = ClinicMembership(
  clinicId: 'personal',
  clinicName: 'Mi espacio personal',
  userId: 'user-a',
  role: ClinicRole.admin,
  workspaceKind: 'personal',
);

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
          'title': 'Mi chat',
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
    'can_manage': true,
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

class PersonalAuthFake extends FakeAuth implements PersonalWorkspaceRepository {
  bool created = false;
  @override
  Future<void> createPersonalWorkspace() async {
    created = true;
  }

  @override
  Future<List<ClinicMembership>> memberships() async => [
    member,
    if (created) personal,
  ];
}

void main() {
  test(
    'Entering personal workspace selects it without a clinic invitation',
    () async {
      final repo = PersonalAuthFake();
      final vm = AuthViewModel(repo);
      await vm.start();
      expect(vm.active, member);
      await vm.createPersonalWorkspace();
      expect(vm.active?.isPersonal, true);
      expect(vm.active?.clinicId, 'personal');
      vm.dispose();
      await repo.controller.close();
    },
  );
  test('AI clears previous messages when access is revoked', () async {
    final repo = AiFake();
    final vm = AiViewModel(repo, 'personal');
    await vm.load(chat: 'chat');
    expect(vm.messages, hasLength(1));
    repo.fail = true;
    await vm.load();
    expect(vm.messages, isEmpty);
    expect(vm.selected, isNull);
    vm.dispose();
  });
  test(
    'A stale AI response cannot overwrite a new selection or disposed model',
    () async {
      final repo = AiFake();
      final vm = AiViewModel(repo, 'personal');
      final stale = Completer<Map<String, dynamic>>();
      repo.delayed = stale;
      final a = vm.load(chat: 'chat');
      repo.delayed = null;
      await vm.load();
      stale.complete({'chats': [], 'connections': []});
      await a;
      expect(vm.rows('chats'), hasLength(1));
      vm.dispose();
    },
  );
  testWidgets(
    'Individual annual price is shown but purchasing is disabled until published',
    (tester) async {
      final repo = PlanFake();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SubscriptionScreen(repository: repo, member: personal),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('199.00 MXN'), findsOneWidget);
      await tester.tap(find.text('Anual'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1990.00 MXN'), findsOneWidget);
      expect(find.textContaining('Abrir pago seguro'), findsNothing);
      await tester.ensureVisible(find.text('Registrar interés (sin cobro)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar interés (sin cobro)'));
      await tester.pumpAndSettle();
      expect(repo.requests, 1);
      expect(find.textContaining('No hubo cobro'), findsOneWidget);
    },
  );
  testWidgets(
    'Personal AI shows privacy controls but does not offer shared context',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiScreen(repository: AiFake(), member: personal),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi chat · Solo yo').last);
      await tester.pumpAndSettle();
      expect(find.text('Privado'), findsOneWidget);
      expect(
        find.text('Usar chats compartidos autorizados para mi rol'),
        findsNothing,
      );
      expect(find.text('Solicitar respuesta'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Solicitar respuesta'),
      );
      expect(button.onPressed, isNull);
    },
  );
}
