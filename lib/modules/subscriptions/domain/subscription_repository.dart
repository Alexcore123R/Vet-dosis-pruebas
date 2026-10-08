abstract interface class SubscriptionRepository {
  Future<Map<String, dynamic>> dashboard(String clinic);
  Future<String> checkout(String request);
  Future<void> redeem(String clinic, String operation);
  Future<void> request(
    String clinic,
    String plan,
    String period,
    String operation,
  );
}

abstract interface class PaymentHistoryRepository {
  Future<List<Map<String, dynamic>>> paymentHistory(String clinic);
}
