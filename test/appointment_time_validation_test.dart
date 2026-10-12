import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/operations/presentation/operations_view_model.dart';

void main() {
  test('Rejects the reversed interval reported on Android', () {
    expect(
      () => validateAppointmentTimes({
        'starts_at': '2026-10-12T17:56:00-06:00',
        'ends_at': '2026-10-12T09:31:00-06:00',
      }),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('posteriores'),
        ),
      ),
    );
  });
  test('Validates absolute time across dates and timezone offsets', () {
    expect(
      () => validateAppointmentTimes({
        'starts_at': '2026-10-12T23:50:00-06:00',
        'ends_at': '2026-10-13T06:20:00Z',
      }),
      returnsNormally,
    );
    expect(
      () => validateAppointmentTimes({
        'starts_at': '2026-10-12T23:50:00-06:00',
        'ends_at': '2026-10-13T05:50:00Z',
      }),
      throwsFormatException,
    );
  });
  test('Rejects missing timestamps and durations over one day', () {
    expect(() => validateAppointmentTimes({}), throwsFormatException);
    expect(
      () => validateAppointmentTimes({
        'starts_at': '2026-10-12T10:00:00Z',
        'ends_at': '2026-10-13T10:01:00Z',
      }),
      throwsFormatException,
    );
  });
}
