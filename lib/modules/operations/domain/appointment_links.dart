import '../../inventory/domain/inventory_models.dart';

abstract interface class AppointmentLinksRepository {
  Future<Map<String, Map<String, dynamic>>> patientLinks(
    String clinic,
    List<String> appointments,
  );
}

class AppointmentBilling {
  const AppointmentBilling(this.state, this.total, this.paid);
  final String state;
  final Money total, paid;
  Money get remaining => total - paid;
  factory AppointmentBilling.read(Map<String, dynamic> raw) {
    if (raw['total'] is! String ||
        raw['paid'] is! String ||
        raw['charge_count'] is! int) {
      throw const FormatException('Estado de pago no compatible.');
    }
    final total = Money.parse(raw['total'] as String),
        paid = Money.parse(raw['paid'] as String);
    final count = raw['charge_count'] as int;
    if (count < 0 ||
        paid.cents > total.cents ||
        (count == 0 &&
            (total.cents != BigInt.zero || paid.cents != BigInt.zero))) {
      throw const FormatException('Importes pendientes de revisión.');
    }
    final state = count == 0
        ? 'no_charge'
        : paid.cents == total.cents
        ? 'paid'
        : paid.cents == BigInt.zero
        ? 'unpaid'
        : 'partial';
    if (raw['state'] != state) {
      throw const FormatException('Importes pendientes de revisión.');
    }
    return AppointmentBilling(state, total, paid);
  }
  String get label => switch (state) {
    'no_charge' => 'Sin cargo registrado',
    'paid' => 'Pagado · ${paid.display}',
    'unpaid' => 'Pendiente de pago · ${total.display}',
    _ => 'Abonado: ${paid.display} · Restante: ${remaining.display}',
  };
}
