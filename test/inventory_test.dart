import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/doses/domain/quantity.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_models.dart';
import 'package:vetdosis_pro/modules/inventory/domain/inventory_repository.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/inventory_view_model.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/inventory_screen.dart';
import 'package:vetdosis_pro/modules/inventory/presentation/sale_screen.dart';

const member = ClinicMembership(
  clinicId: 'clinic',
  clinicName: 'Ficticia',
  userId: 'aux',
  role: ClinicRole.auxiliar,
);
Map<String, dynamic> data() => {
  'today': '2026-10-07',
  'timezone': 'America/Mexico_City',
  'professional': false,
  'products': [
    {
      'id': 'product',
      'nombre': 'Producto ficticio',
      'presentacion': 'Unidad ficticia',
      'stock': '3',
      'stock_minimo': '1',
      'reorder_point': '2',
      'available_stock': '2',
      'low_stock': false,
      'reorder': true,
      'm8_enabled': true,
      'm8_kind': 'producto',
      'stock_unit': 'unidad',
      'active': true,
      'precio_venta': '0.10',
      'codigo_barras': 'FICTICIO',
      'lots': [
        {
          'id': 'lot',
          'lote': 'Lote ficticio',
          'cantidad': '2',
          'caducidad': '2026-10-20',
          'days': 13,
          'expired': false,
        },
      ],
    },
  ],
  'shifts': [],
  'orders': [],
  'catalog': [],
  'staff': [],
  'prescription_items': [],
};

class Repo implements InventoryRepository {
  bool fail = false;
  Completer<dynamic>? pending;
  final List<Map<String, dynamic>> writes = [];
  @override
  Future<dynamic> read(String command, Map<String, dynamic> args) async {
    if (fail) throw StateError('Denied');
    if (pending != null) return pending!.future;
    if (command == 'inv_shift_snapshot') {
      return {'shift_id': 'test', 'totals': {}, 'sales': []};
    }
    return data();
  }

  @override
  Future<dynamic> write(String command, Map<String, dynamic> args) async {
    writes.add({'command': command, ...args});
    return 'id';
  }

  @override
  Future<void> photo(
    String clinic,
    String product,
    int version,
    Uint8List bytes,
    String extension,
  ) async {}
  @override
  Future<String> photoUrl(String path) async => 'https://example.test';
}

void main() {
  test('Money uses exact cents, comma input and known decimal subtotal', () {
    expect((Money.parse('0.10') + Money.parse('0,20')).decimal, '0.30');
    expect(Money.parse('0.10').times(Quantity.parse('3')).decimal, '0.30');
    expect(Money.parse('0.01').times(Quantity.parse('0.5')).decimal, '0.01');
    expect((Money.parse('1') - Money.parse('2')).decimal, '-1.00');
    expect(Money.parse('-1.01', signed: true).display, '\$-1,01 MXN');
  });
  test('Money rejects ambiguous input and fractional cent prices', () {
    for (final v in ['1.234', '1,000.00', 'NaN', '1e2', '-1']) {
      expect(() => Money.parse(v), throwsFormatException);
    }
    expect(displayMoney('1.234'), contains('revisión'));
    expect(() => stockQuantity('0'), throwsFormatException);
    expect(stockQuantity('0', zero: true), '0');
  });
  test('30/60 day alerts and expired day zero preserve missing date', () {
    expect(expiryLabel({'caducidad': 'x', 'days': 0}), contains('CADUCADO'));
    expect(expiryLabel({'caducidad': 'x', 'days': 30}), contains('30 días'));
    expect(expiryLabel({'caducidad': 'x', 'days': 60}), contains('60 días'));
    expect(expiryLabel({'caducidad': null}), contains('Sin caducidad'));
  });
  test(
    'Cut CSV freezes declared money, escapes formulas and includes reversals',
    () {
      final csv = cutCsv({
        'shift_id': 'test',
        'totals': {'gross': '0.30', 'commission': '0.10'},
        'sales': [
          {
            'id': 'sale',
            'total': '0.30',
            'lines': [
              {
                'name': '=IMPORTXML("test")',
                'quantity': '3',
                'price': '0.10',
                'total': '0.30',
              },
            ],
          },
        ],
        'reversals': [
          {'sale_id': 'old', 'reason': 'Reverso ficticio'},
        ],
      });
      expect(csv, contains("'=IMPORTXML"));
      expect(csv, contains('0.30'));
      expect(csv, contains('Reverso ficticio'));
      expect(csv.startsWith('\uFEFF'), true);
      expect(csv, contains('no comprobante fiscal'));
    },
  );
  test(
    'Privileged errors explain source, authorized total and revoked delegation',
    () {
      expect(
        inventoryError(StateError('quantified_dispensing_professional_only')),
        contains('MVZ habilitado'),
      );
      expect(
        inventoryError(StateError('dispensing_authorized_quantity_exceeded')),
        contains('ventas anteriores'),
      );
      expect(
        inventoryError(StateError('ordinary_dispensing_delegation_required')),
        contains('permiso vigente'),
      );
    },
  );
  test('Failed refresh clears private financial data', () async {
    final r = Repo();
    final m = InventoryViewModel(r, member);
    await m.load();
    await m.readCut('id');
    expect(m.cut, isNotNull);
    r.fail = true;
    await m.load();
    expect(m.dashboard, isNull);
    expect(m.cut, isNull);
    expect(m.error, isNotNull);
    m.dispose();
  });
  test('Delayed response cannot repopulate a disposed screen', () async {
    final r = Repo()..pending = Completer<dynamic>();
    final m = InventoryViewModel(r, member);
    final loading = m.load();
    m.dispose();
    r.pending!.complete(data());
    await loading;
    expect(m.dashboard, isNull);
  });
  test('Old cut cannot replace a refreshed dashboard', () async {
    final r = Repo();
    final m = InventoryViewModel(r, member);
    await m.load();
    r.pending = Completer<dynamic>();
    final waiting = m.readCut('id');
    final pending = r.pending!;
    r.pending = null;
    await m.load();
    pending.complete({'totals': {}, 'sales': []});
    await waiting;
    expect(m.cut, isNull);
    m.dispose();
  });
  testWidgets(
    'Inventory fits phone, shows dates and does not expose admin operations to auxiliary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: InventoryScreen(repository: Repo(), member: member),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Producto ficticio'), findsOneWidget);
      expect(find.textContaining('alerta 30 días'), findsOneWidget);
      expect(find.text('Nuevo producto'), findsNothing);
      expect(find.text('Foto con cámara'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'sin coincidencia');
      await tester.pump();
      expect(find.textContaining('Producto ficticio'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Empty cart cannot register a sale without lines or review', (
    tester,
  ) async {
    final repo = Repo();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleScreen(
          repository: repo,
          shift: 'test',
          products: [],
          prescriptions: [],
          staff: [],
          admin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total a pagar: \$0,00 MXN'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(repo.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Reviewed cart submits exact quantity, lot, payment and total', (
    tester,
  ) async {
    final repo = Repo();
    await tester.pumpWidget(
      MaterialApp(
        home: SaleScreen(
          repository: repo,
          shift: 'test',
          products: (data()['products'] as List).cast<Map<String, dynamic>>(),
          prescriptions: [],
          staff: [],
          admin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_shopping_cart));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lote ficticio · 2 · 2026-10-20').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '2');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Total a pagar: \$0,20 MXN'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Registrar venta y pago'));
    await tester.tap(find.text('Registrar venta y pago'));
    await tester.pumpAndSettle();
    expect(repo.writes.single['p_expected_total'], '0.20');
    expect(repo.writes.single['p_method'], 'efectivo');
    final line = (repo.writes.single['p_lines'] as List).single as Map;
    expect(line['quantity'], '2');
    expect(line['lot_id'], 'lot');
    expect(line.containsKey('display'), false);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Reception collects two applications without selling or rededucting a bottle',
    (tester) async {
      final repo = Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: SaleScreen(
            repository: repo,
            shift: 'cashier',
            products: [],
            prescriptions: [],
            staff: [],
            admin: false,
            charges: [
              {
                'id': 'application-one',
                'name': 'Aplicación 0,5 ml · receta única',
                'price': '15.00',
                'paid': false,
              },
              {
                'id': 'application-two',
                'name': 'Siguiente aplicación 0,5 ml · receta única',
                'price': '15.00',
                'paid': false,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pump();
      expect(find.text('Total a pagar: \$30,00 MXN'), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.text('Registrar venta y pago'));
      await tester.tap(find.text('Registrar venta y pago'));
      await tester.pumpAndSettle();
      final lines = (repo.writes.single['p_lines'] as List).cast<Map>();
      expect(lines.length, 2);
      expect(lines.map((l) => l['charge_id']).toSet(), {
        'application-one',
        'application-two',
      });
      expect(
        lines.every(
          (l) =>
              l['kind'] == 'servicio' &&
              l['quantity'] == '1' &&
              !l.containsKey('item_id') &&
              !l.containsKey('lot_id'),
        ),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
