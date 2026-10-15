import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/identity_repository.dart';

class SupabaseIdentityRepository implements IdentityRepository {
  SupabaseIdentityRepository(this.client);
  final SupabaseClient client;
  void requireOwner(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('account_changed');
    }
  }

  @override
  Future<AccountIdentity> account(String userId) async {
    requireOwner(userId);
    final row = Map<String, dynamic>.from(
      await client.rpc('account_identity_get'),
    );
    final path = row['photo_path'] as String?;
    final photo = path == null
        ? null
        : await client.storage.from('account-avatars').download(path);
    requireOwner(userId);
    return AccountIdentity(
      icon: row['icon'] as int? ?? 0,
      configured: row['configured'] == true,
      photo: photo,
    );
  }

  @override
  Future<void> saveAccount(String userId, AccountIdentity identity) async {
    requireOwner(userId);
    final path = '$userId/avatar.png';
    if (identity.photo != null) {
      if (identity.photo!.length > 500000) {
        throw const FormatException('avatar_size');
      }
      await client.storage
          .from('account-avatars')
          .uploadBinary(
            path,
            identity.photo!,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
              cacheControl: '0',
            ),
          );
      requireOwner(userId);
    }
    await client.rpc(
      'account_identity_save',
      params: {'p_icon': identity.icon, 'p_photo': identity.photo != null},
    );
    // One private slot per account. Do not delete it here: a concurrent upload
    // from another device may already have replaced its bytes.
    requireOwner(userId);
  }

  @override
  Future<Map<String, dynamic>> clinic(String clinicId) async {
    try {
      return Map<String, dynamic>.from(
        await client.rpc('clinic_identity_get', params: {'p_clinic': clinicId}),
      );
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202') rethrow;
      // Compatibility while the additive migration awaits deployment. The old
      // endpoint continues to enforce clinical roles; no authorization fallback.
      return Map<String, dynamic>.from(
        await client.rpc('form_branding', params: {'p_clinic': clinicId}),
      );
    }
  }
}
