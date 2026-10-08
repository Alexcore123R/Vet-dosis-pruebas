import '../../doses/domain/quantity.dart';
import '../../prescribing/domain/prescribing_models.dart' show csvCell;

class Money {
  const Money(this.cents);
  final BigInt cents;
  factory Money.parse(String raw, {bool signed = false}) {
    final value = raw.trim().replaceAll(',', '.');
    if (!RegExp(
      signed ? r'^-?\d{1,16}(\.\d{1,2})?$' : r'^\d{1,12}(\.\d{1,2})?$',
    ).hasMatch(value)) {
      throw const FormatException(
        'Importe MXN con máximo dos decimales, sin separadores de miles.',
      );
    }
    final negative = value.startsWith('-');
    final parts = (negative ? value.substring(1) : value).split('.');
    final n =
        BigInt.parse(parts[0]) * BigInt.from(100) +
        BigInt.parse(parts.length == 2 ? parts[1].padRight(2, '0') : '0');
    return Money(negative ? -n : n);
  }
  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money times(Quantity quantity) {
    if (quantity.n < BigInt.zero) {
      throw const FormatException('Cantidad negativa.');
    }
    final n = cents * quantity.n;
    return Money((n * BigInt.two + quantity.d) ~/ (quantity.d * BigInt.two));
  }

  String get decimal {
    final n = cents.abs();
    return '${cents.isNegative ? '-' : ''}${n ~/ BigInt.from(100)}.${(n % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

  String get display => '\$${decimal.replaceAll('.', ',')} MXN';
}

String stockQuantity(String text, {bool zero = false}) {
  final value = text.trim().replaceAll(',', '.');
  final q = Quantity.parse(value);
  if (!zero && !q.positive) {
    throw const FormatException('Cantidad mayor que cero.');
  }
  return value;
}

String expiryLabel(Map<String, dynamic> lot) {
  final days = lot['days'];
  if (lot['caducidad'] == null) return 'Sin caducidad capturada';
  if (lot['expired'] == true || days is int && days <= 0) {
    return 'CADUCADO / bloqueo';
  }
  if (days is int && days <= 30) return 'Caduca en $days días · alerta 30 días';
  if (days is int && days <= 60) return 'Caduca en $days días · alerta 60 días';
  return 'Vigente · ${lot['caducidad']}';
}

String cutCsv(Map<String, dynamic> cut) {
  final totals = Map<String, dynamic>.from(cut['totals'] as Map);
  final rows = <List<Object?>>[
    ['VetDosis Pro', 'CORTE INTERNO · no comprobante fiscal', 'MXN'],
    [
      'Turno',
      cut['shift_id'],
      'Abierto UTC',
      cut['opened_at'],
      'Cierre UTC',
      cut['closed_at'] ?? 'EN CURSO',
      'Zona',
      cut['timezone'],
    ],
    [
      'Fondo inicial',
      cut['opening_cash'],
      'Esperado',
      cut['expected_cash'],
      'Contado',
      cut['counted_cash'],
      'Diferencia',
      cut['difference'],
    ],
    for (final e in totals.entries) [e.key, e.value],
    [
      'Utilidad calculada con gastos capturados; no certifica que todos los gastos estén incluidos.',
    ],
    [
      'Venta',
      'Fecha UTC',
      'Método',
      'Producto / servicio',
      'Lote',
      'Cantidad',
      'Unidad',
      'Precio',
      'Importe',
      'Costo',
      'Comisión',
      'Profesional',
    ],
    for (final s in (cut['sales'] as List? ?? []).cast<Map>())
      for (final l in (s['lines'] as List? ?? []).cast<Map>())
        [
          s['id'],
          s['created_at'],
          s['method'],
          l['name'],
          l['lot'],
          l['quantity'],
          l['stock_unit'],
          l['price'],
          l['total'],
          l['cost'],
          l['commission'],
          l['professional_id'],
        ],
    ['REVERSOS DEL TURNO'],
    for (final r in (cut['reversals'] as List? ?? []).cast<Map>())
      [r['sale_id'], r['created_at'], r['reason']],
    ['MOVIMIENTOS DE EFECTIVO'],
    for (final m in (cut['cash_movements'] as List? ?? []).cast<Map>())
      [m['kind'], m['amount'], m['reason'], m['created_at']],
  ];
  return '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

String displayMoney(Object? raw, {bool signed = false}) {
  try {
    return Money.parse(raw.toString(), signed: signed).display;
  } on FormatException {
    return 'Importe pendiente de revisión';
  }
}
