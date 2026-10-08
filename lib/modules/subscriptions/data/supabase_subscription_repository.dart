import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/subscription_repository.dart';

class SupabaseSubscriptionRepository
    implements SubscriptionRepository, PaymentHistoryRepository {
  SupabaseSubscriptionRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<Map<String, dynamic>>> paymentHistory(String clinic) async =>
      (await client.rpc('plan_payment_history', params: {'p_clinic': clinic})
              as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> dashboard(String clinic) async =>
      Map<String, dynamic>.from(
        await client.rpc('plan_dashboard', params: {'p_clinic': clinic}) as Map,
      );
  @override
  Future<String> checkout(String request) async {
    final r = await client.functions.invoke(
      'subscriptions-gateway',
      body: {'request': request},
    );
    if (r.status != 200 || r.data['url'] is! String) {
      throw const FormatException(
        'Cobro no configurado o precios todavía en borrador.',
      );
    }
    return r.data['url'] as String;
  }

  @override
  Future<void> redeem(String clinic, String operation) async {
    await client.rpc(
      'reward_redeem',
      params: {'p_clinic': clinic, 'p_operation': operation},
    );
  }

  @override
  Future<void> request(
    String clinic,
    String plan,
    String period,
    String operation,
  ) async {
    await client.rpc(
      'plan_request',
      params: {
        'p_clinic': clinic,
        'p_code': plan,
        'p_period': period,
        'p_operation': operation,
      },
    );
  }
}
