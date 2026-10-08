abstract interface class AiRepository {
  Future<Map<String, dynamic>> dashboard(String clinic);
  Future<String> create(String clinic, String title, String operation);
  Future<List<Map<String, dynamic>>> messages(String chat);
  Future<void> policy(
    String chat,
    int version,
    String visibility,
    String context,
    List<String> audience,
  );
  Future<void> abandon(String chat);
  Future<void> delete(String chat);
  Future<void> saveKey(
    String provider,
    String scope,
    String clinic,
    String key,
  );
  Future<void> disableKey(String connection);
  Future<List<Map<String, dynamic>>> models(String connection);
  Future<void> send(
    String chat,
    String connection,
    String model,
    String message,
    String operation,
    bool personal,
    bool team,
  );
}

abstract interface class StarterAiRepository {
  Future<Map<String, dynamic>> starterStatus(String clinic);
  Future<String> starterHelp(String clinic, String topic, String operation);
}
