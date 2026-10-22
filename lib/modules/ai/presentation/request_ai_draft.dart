import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/ai_repository.dart';
import 'ai_screen.dart';

/// Returns only a response explicitly selected by the user for review/editing.
Future<String?> requestAiDraft(BuildContext context, {
  required AiRepository repository,
  required ClinicMembership member,
  required String title,
  required String prompt,
}) => Navigator.push<String>(context, MaterialPageRoute(builder: (_) => Scaffold(
  appBar: AppBar(title: Text(title)),
  body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: AiScreen(
    repository: repository, member: member, initialDraft: prompt,
    draftTitle: title, returnDraft: true,
  )),
)));

Future<String?> reviewAiDraft(BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: TextField(
        controller: controller, maxLines: null, maxLength: 12000,
        decoration: const InputDecoration(labelText: 'Revisar y editar borrador'),
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: controller.text)); }, child: const Text('Copiar')),
        FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Usar texto revisado'))],
    ));
  } finally { controller.dispose(); }
}
