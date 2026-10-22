String promotionMessage(Map<String, dynamic> promotion) => [
  '${promotion['title'] ?? ''}',
  '${promotion['message'] ?? ''}',
  if ('${promotion['service_name'] ?? ''}'.isNotEmpty)
    'Servicio / producto: ${promotion['service_name']}',
  if (promotion['discount_percent'] != null &&
      '${promotion['discount_percent']}'.isNotEmpty)
    'Descuento: ${promotion['discount_percent']}%',
  if (promotion['starts_on'] != null || promotion['ends_on'] != null)
    'Vigencia: ${promotion['starts_on'] ?? 'sin inicio'} a ${promotion['ends_on'] ?? 'sin fin'}',
  if ('${promotion['conditions'] ?? ''}'.isNotEmpty)
    'Condiciones: ${promotion['conditions']}',
].where((s) => s.trim().isNotEmpty).join('\n\n');
