import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/core/domain/build_channel.dart';

void main() {
  test('Beta callback is separate from legacy installation', () {
    expect(
      nativeAuthRedirect('beta'),
      'io.github.alexcore123r.vetdosis.beta://login-callback/',
    );
    expect(nativeAuthRedirect(''), 'com.vetdosis.pro://login-callback/');
  });
  test(
    'Beta accepts only approved test backend in release as well as debug',
    () {
      expect(
        () => validateBuildBackend('beta', betaSupabaseUrl),
        returnsNormally,
      );
      for (final url in [
        '',
        'https://other.supabase.co',
        '$betaSupabaseUrl.attacker.test',
      ]) {
        expect(() => validateBuildBackend('beta', url), throwsFormatException);
      }
      expect(() => validateBuildBackend('', ''), returnsNormally);
    },
  );
}
