const betaSupabaseUrl = 'https://wtrelwtztkddfktrfdpb.supabase.co';

void validateBuildBackend(String channel, String url) {
  if (channel == 'beta' && url != betaSupabaseUrl) {
    throw const FormatException(
      'La beta solo puede conectarse al proyecto de pruebas aprobado.',
    );
  }
}

String nativeAuthRedirect(String channel) => channel == 'beta'
    ? 'io.github.alexcore123r.vetdosis.beta://login-callback/'
    : 'com.vetdosis.pro://login-callback/';
