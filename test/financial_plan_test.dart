import 'package:shared_preferences/shared_preferences.dart';
import 'package:vetdosis_pro/core/app.dart';
import 'package:vetdosis_pro/modules/auth/presentation/auth_view_model.dart';
import 'package:vetdosis_pro/modules/core/data/settings_repository.dart';
import 'package:vetdosis_pro/modules/core/presentation/core_view_model.dart';
import 'support/fake_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/finance/domain/financial_plan.dart';
import 'package:vetdosis_pro/modules/finance/presentation/financial_planning_panel.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/core/domain/module_access.dart';
import 'package:vetdosis_pro/modules/core/domain/navigation_access.dart';
import 'module_navigation_dashboard_test.dart' show contract;

FinancialPlan plan({
  int income = 2350000,
  int variable = 900000,
  int fixed = 2450000,
  int depreciation = 0,
  int investment = 10000000,
  int funds = 3350000,
  int reserve = 150000,
}) => FinancialPlan(
  income: income,
  variableCosts: variable,
  fixedCosts: fixed,
  depreciation: depreciation,
  investment: investment,
  availableFunds: funds,
  reserve: reserve,
);

void main() {
  test('Academic loss is reproduced without treating reserve as a cost', () {
    final result = plan();
    expect(result.estimatedResult, -1000000);
    expect(result.operatingCash, -1000000);
    expect(result.fundingGap, 10150000);
    expect(result.recoveryMonths, isNull);
  });
  test(
    'Noncash depreciation is separate from funds and monthly operating cash',
    () {
      final result = plan(
        income: 5000000,
        variable: 1000000,
        fixed: 2000000,
        depreciation: 500000,
      );
      expect(result.operatingCash, 2000000);
      expect(result.estimatedResult, 1500000);
      expect(result.breakEvenIncome, closeTo(3125000, .001));
      expect(result.recoveryMonths, 5);
      expect(
        result.fundingGap,
        plan(income: 5000000, variable: 1000000, fixed: 2000000).fundingGap,
      );
    },
  );
  test('Zero receipts or nonpositive margin has no invented equilibrium', () {
    expect(plan(income: 0).breakEvenIncome, isNull);
    expect(plan(income: 900000).breakEvenIncome, isNull);
    expect(plan(income: 1).breakEvenIncome, isNull);
    expect(plan(income: 3350000).recoveryMonths, isNull);
    expect(plan(funds: 100000000000).fundingGap, 0);
    expect(() => plan(income: -1), throwsArgumentError);
  });
  test(
    'Amount parsing keeps cents and refuses ambiguous or nonfinite values',
    () {
      expect(parsePlanAmount(' 123,45 '), 12345);
      expect(parsePlanAmount('0.1'), 10);
      expect(parsePlanAmount('1000000000'), 100000000000);
      for (final value in [
        '',
        '-1',
        'NaN',
        'Infinity',
        '1e3',
        '1,234.56',
        '1.234',
        '1000000000.01',
      ]) {
        expect(parsePlanAmount(value), isNull, reason: value);
      }
    },
  );
  test(
    'Planning requires administrator and existing financial module access',
    () {
      for (final role in ClinicRole.values) {
        final member = ClinicMembership(
          clinicId: 'a',
          clinicName: 'Demo',
          userId: 'u',
          role: role,
        );
        expect(
          navigationAllowed(
            'Planeación financiera',
            member,
            ModuleAccess.read(contract(enabled: 'sales')),
          ),
          role == ClinicRole.admin,
        );
        expect(
          navigationAllowed(
            'Planeación financiera',
            member,
            ModuleAccess.denied,
          ),
          false,
        );
      }
    },
  );
  testWidgets(
    'Empty scenario is rejected and changing input clears stale results',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: FinancialPlanningPanel()),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Calcular escenario'));
      await tester.tap(find.text('Calcular escenario'));
      await tester.pumpAndSettle();
      expect(find.text('Resultado del escenario'), findsNothing);
      expect(find.textContaining('Introduce de 0 a'), findsNWidgets(7));
      final values = ['23500', '24500', '9000', '0', '100000', '33500', '1500'];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      await tester.ensureVisible(find.text('Calcular escenario'));
      await tester.tap(find.text('Calcular escenario'));
      await tester.pumpAndSettle();
      expect(find.textContaining('-10000.00 MXN'), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).first, '30000');
      await tester.pump();
      expect(find.text('Resultado del escenario'), findsNothing);
      await tester.ensureVisible(find.text('Limpiar simulación'));
      await tester.tap(find.text('Limpiar simulación'));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets('Simulator remains readable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: FinancialPlanningPanel()),
        ),
      ),
    );
    for (var i = 0; i < 7; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), '0');
    }
    await tester.ensureVisible(find.text('Calcular escenario'));
    await tester.tap(find.text('Calcular escenario'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.textContaining('Estimaciones antes de impuestos'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Host rejects a direct restricted route and clears amounts on exit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = FakeAuth();
      final auth = AuthViewModel(repo);
      await auth.start();
      final core = CoreViewModel(SettingsRepository(), const AppSettings())
        ..navigate('Planeación financiera');
      Widget app([ModuleAccess? access]) => MaterialApp(
        home: CoreShell(model: core, auth: auth, moduleAccess: access),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(FinancialPlanningPanel), findsNothing);
      repo.rows = [
        const ClinicMembership(
          clinicId: 'a',
          clinicName: 'Demo A',
          userId: 'user-a',
          role: ClinicRole.admin,
        ),
      ];
      await auth.start();
      final access = ModuleAccess.read(contract(enabled: 'sales'));
      await tester.pumpWidget(app(access));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '123');
      repo.rows = [
        const ClinicMembership(
          clinicId: 'b',
          clinicName: 'Demo B',
          userId: 'user-a',
          role: ClinicRole.admin,
        ),
      ];
      await auth.start();
      await tester.pumpWidget(app(access));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField).first, '456');
      await tester.pumpWidget(app(ModuleAccess.denied));
      await tester.pumpAndSettle();
      expect(find.byType(FinancialPlanningPanel), findsNothing);
      await tester.pumpWidget(app(access));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      core.navigate('Cálculos');
      await tester.pumpWidget(app(access));
      await tester.pumpAndSettle();
      core.navigate('Planeación financiera');
      await tester.pumpWidget(app(access));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      core.dispose();
      auth.dispose();
      await repo.controller.close();
    },
  );
}
