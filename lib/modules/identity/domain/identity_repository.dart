import 'dart:typed_data';

class AccountIdentity {
  const AccountIdentity({this.icon = 0, this.photo, this.configured = true});
  final int icon;
  final bool configured;
  final Uint8List? photo;
}

abstract interface class IdentityRepository {
  Future<AccountIdentity> account(String userId);
  Future<void> saveAccount(String userId, AccountIdentity identity);
  Future<Map<String, dynamic>> clinic(String clinicId);
}
