const aiProviderLabels = {
  'google': 'Gemini (Google)',
  'zai': 'GLM (Z.AI)',
  'openai': 'OpenAI',
  'anthropic': 'Anthropic',
};
String aiScopeLabel(dynamic scope) =>
    {'personal': 'Solo mi cuenta', 'clinic': 'Mi clínica'}[scope] ?? '$scope';
String aiVisibilityLabel(dynamic visibility) =>
    {
      'private': 'Solo yo',
      'clinic': 'Compartido con roles elegidos',
    }[visibility] ??
    '$visibility';
String aiContextLabel(dynamic mode) =>
    {
      'none': 'Excluido de otros chats',
      'personal': 'Solo contexto personal',
      'clinic': 'Contexto compartido autorizado',
    }[mode] ??
    '$mode';
