import 'ai_labels.dart';
import 'starter_help_panel.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/ai_repository.dart';
import 'ai_view_model.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({
    super.key,
    required this.repository,
    required this.member,
    this.initialDraft,
    this.draftTitle = 'Ayuda de soporte',
    this.returnDraft = false,
    this.canManageWorkspace = false,
    this.configurationOnly = false,
  });
  final AiRepository repository;
  final ClinicMembership member;
  final String? initialDraft;
  final String draftTitle;
  final bool returnDraft;
  final bool canManageWorkspace;
  final bool configurationOnly;
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  late final vm = AiViewModel(widget.repository, widget.member.clinicId);
  bool get canManageWorkspace =>
      widget.canManageWorkspace || vm.data['can_manage'] == true;
  final composer = TextEditingController();
  String? connection, model;
  List<Map<String, dynamic>> modelOptions = [];
  bool working = false, personal = false, team = false, consent = false;
  String operation = newOperationId();
  @override
  void initState() {
    super.initState();
    if (widget.initialDraft != null) {
      composer.text = widget.initialDraft!;
      initializeSupportChat();
    } else {
      vm.load();
    }
  }

  Future<void> initializeSupportChat() async {
    await run(() async {
      final id = await widget.repository.create(
        widget.member.clinicId,
        widget.draftTitle,
        newOperationId(),
      );
      await vm.load(chat: id);
    });
  }

  @override
  void dispose() {
    composer.dispose();
    vm.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() f) async {
    if (working) return;
    setState(() => working = true);
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'No se completó la acción. Revisa conexión y permisos.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Map<String, dynamic>? get current =>
      vm.rows('chats').where((c) => c['id'] == vm.selected).firstOrNull;
  bool get own => current?['owner_id'] == widget.member.userId;
  Future<void> newChat() async {
    final text = TextEditingController();
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Nuevo chat privado'),
          content: TextField(
            controller: text,
            maxLength: 150,
            decoration: const InputDecoration(labelText: 'Título'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, text.text.trim()),
              child: const Text('Crear'),
            ),
          ],
        ),
      );
      if (title == null || title.isEmpty) return;
      await run(() async {
        final id = await widget.repository.create(
          widget.member.clinicId,
          title,
          newOperationId(),
        );
        await vm.load(chat: id);
      });
    } finally {
      text.dispose();
    }
  }

  Future<void> key() async {
    final controller = TextEditingController();
    String provider = 'google', scope = 'personal';
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: const Text('Proveedor y API key'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: provider,
                    items: [
                      for (final p in ['google', 'zai', 'openai', 'anthropic'])
                        DropdownMenuItem(
                          value: p,
                          child: Text(aiProviderLabels[p] ?? p),
                        ),
                    ],
                    onChanged: (v) => set(() => provider = v!),
                  ),
                  if (canManageWorkspace &&
                      !widget.member.isPersonal)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: scope,
                      items: const [
                        DropdownMenuItem(
                          value: 'personal',
                          child: Text('Solo mi cuenta'),
                        ),
                        DropdownMenuItem(
                          value: 'clinic',
                          child: Text('Clave compartida de la clínica'),
                        ),
                      ],
                      onChanged: (v) => set(() => scope = v!),
                    ),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'API key (no se mostrará después)',
                    ),
                  ),
                  const Text(
                    'El proveedor aplica sus precios o cuotas gratuitas. Los textos elegidos se enviarán allí al solicitar una respuesta. En Gemini gratuito no debes enviar información sensible, personal ni confidencial.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Guardar clave'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      await run(() async {
        await widget.repository.saveKey(
          provider,
          scope,
          widget.member.clinicId,
          controller.text.trim(),
        );
        controller.clear();
        await vm.load();
      });
    } finally {
      controller.clear();
      controller.dispose();
    }
  }

  Future<void> rotateKey(String connectionId) async {
    String newKey = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renovar API key'),
        content: TextField(
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          onChanged: (value) => newKey = value,
          decoration: const InputDecoration(
            labelText: 'Nueva API key',
            helperText: 'La clave anterior dejará de utilizarse en nuevas solicitudes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Renovar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await run(() async {
      await widget.repository.rotateKey(connectionId, newKey.trim());
      newKey = '';
      await vm.load();
    });
    newKey = '';
  }

  Future<void> editPolicy() async {
    final chat = current!;
    String visibility = chat['visibility'] as String,
        mode = chat['context_mode'] as String;
    final audience = (chat['audience'] as List).cast<String>().toSet();
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Privacidad y contexto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: visibility,
                  decoration: const InputDecoration(
                    labelText: 'Quién puede leer',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'private',
                      child: Text('Solo yo'),
                    ),
                    if (!widget.member.isPersonal)
                      const DropdownMenuItem(
                        value: 'clinic',
                        child: Text('Roles elegidos de mi clínica'),
                      ),
                  ],
                  onChanged: (v) => set(() {
                    visibility = v!;
                    if (visibility == 'private' && mode == 'clinic') {
                      mode = 'none';
                    }
                  }),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('$visibility:$mode'),
                  initialValue: mode,
                  decoration: const InputDecoration(
                    labelText: 'Uso como contexto de otros chats',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'none',
                      child: Text('No usar como contexto'),
                    ),
                    const DropdownMenuItem(
                      value: 'personal',
                      child: Text('Solo mi contexto personal'),
                    ),
                    if (visibility == 'clinic')
                      const DropdownMenuItem(
                        value: 'clinic',
                        child: Text('Contexto compartido para roles elegidos'),
                      ),
                  ],
                  onChanged: (v) => set(() => mode = v!),
                ),
                if (visibility == 'clinic')
                  Wrap(
                    children: [
                      for (final r in ClinicRole.values)
                        FilterChip(
                          label: Text(r.label),
                          selected: audience.contains(r.name),
                          onSelected: (yes) => set(
                            () => yes
                                ? audience.add(r.name)
                                : audience.remove(r.name),
                          ),
                        ),
                    ],
                  ),
                const Text(
                  'Retirar acceso evita usos futuros. No elimina respuestas ya generadas ni información enviada al proveedor. No compartas datos sensibles con roles que no deban conocerlos.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Guardar ajustes'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await run(() async {
        await widget.repository.policy(
          chat['id'] as String,
          chat['version'] as int,
          visibility,
          mode,
          audience.toList(),
        );
        await vm.load();
      });
    }
  }

  Future<void> export() async {
    await FilePicker.saveFile(
      fileName: 'chat-${vm.selected}.json',
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'chat': current, 'messages': vm.messages})),
      ),
    );
  }

  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar este chat'),
        content: const Text(
          'Se borrarán su historial y su uso futuro como contexto en la app. No elimina copias o respuestas anteriores del proveedor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await run(() async {
        await widget.repository.delete(vm.selected!);
        await vm.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.configurationOnly) ...[
          Text('Proveedores de IA y privacidad', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Administra claves personales o de clínica. Las claves no se vuelven a mostrar.'),
          if (vm.busy || working) const LinearProgressIndicator(),
          if (vm.error != null) Text(vm.error!),
          FilledButton(onPressed: working ? null : key, child: const Text('Agregar proveedor / clave')),
          for (final k in vm.rows('connections'))
            if (k['can_manage'] == true)
              ListTile(
                title: Text("${aiProviderLabels[k['provider']] ?? k['provider']} · ${aiScopeLabel(k['scope'])}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: working ? null : () => rotateKey(k['id'] as String),
                      child: const Text('Renovar'),
                    ),
                    TextButton(
                      onPressed: working ? null : () => run(() async {
                        await widget.repository.disableKey(k['id'] as String);
                        await vm.load();
                      }),
                      child: const Text('Revocar'),
                    ),
                  ],
                ),
              ),
          const Text('La privacidad de cada conversación se administra desde su chat.'),
        ] else ...[
        Text('Asistente IA', style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Apoyo con IA · respuestas sin verificar. Dosis, normativa y cálculos requieren fuentes verificadas y el motor clínico; este chat no emite recetas ni registra actos.',
        ),
        if (widget.repository is StarterAiRepository)
          StarterHelpPanel(
            repository: widget.repository as StarterAiRepository,
            clinic: widget.member.clinicId,
            onCompleted: (id) async {
              if (!mounted) return;
              setState(() {
                composer.clear();
                consent = false;
                personal = false;
                team = false;
                operation = newOperationId();
              });
              await vm.load(chat: id);
            },
          ),
        if (vm.busy || working) const LinearProgressIndicator(),
        if (vm.error != null) Text(vm.error!),
        Text(
          'Chat con clave propia · solicitudes hoy (UTC): ${vm.data['daily_used'] ?? '—'} / ${vm.data['daily_limit'] ?? '—'}',
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: working ? null : newChat,
              child: const Text('Nuevo chat'),
            ),
            IconButton(
              onPressed: working ? null : vm.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(vm.selected),
          initialValue: vm.selected,
          decoration: const InputDecoration(
            labelText: 'Historial propio y chats compartidos autorizados',
          ),
          items: [
            for (final c in vm.rows('chats'))
              DropdownMenuItem(
                value: c['id'] as String,
                child: Text(
                  '${c['title']} · ${aiVisibilityLabel(c['visibility'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: working
              ? null
              : (id) {
                  composer.clear();
                  consent = false;
                  operation = newOperationId();
                  vm.load(chat: id);
                },
        ),
        if (current != null) ...[
          Text('Contexto futuro: ${aiContextLabel(current!['context_mode'])}'),
          Wrap(
            children: [
              if (own)
                TextButton(
                  onPressed: working ? null : editPolicy,
                  child: const Text('Privacidad / contexto'),
                ),
              TextButton(
                onPressed: working ? null : () => run(export),
                child: const Text('Exportar chat'),
              ),
              if (own)
                TextButton(
                  onPressed: working ? null : delete,
                  child: const Text('Eliminar'),
                ),
            ],
          ),
          for (final m in vm.messages)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['role'] == 'assistant'
                          ? 'IA · sin verificar'
                          : 'Usuario',
                    ),
                    SelectableText(m['body'] as String),
                    if (widget.returnDraft && m['role'] == 'assistant')
                      TextButton.icon(
                        onPressed: working ? null : () => Navigator.pop(context, m['body'] as String),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Usar como borrador editable'),
                      ),
                  ],
                ),
              ),
            ),
        ],
        if (own) ...[
          TextButton(
            onPressed: working
                ? null
                : () => run(() async {
                    await widget.repository.abandon(vm.selected!);
                    await vm.load();
                  }),
            child: const Text('Cerrar solicitud trabada (más de 2 minutos)'),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(connection),
            initialValue:
                vm.rows('connections').any((c) => c['id'] == connection)
                ? connection
                : null,
            decoration: const InputDecoration(
              labelText: 'Proveedor / clave para esta solicitud',
            ),
            items: [
              for (final c in vm.rows('connections'))
                DropdownMenuItem(
                  value: c['id'] as String,
                  child: Text(
                    '${aiProviderLabels[c['provider']] ?? c['provider']} · ${aiScopeLabel(c['scope'])}',
                  ),
                ),
            ],
            onChanged: working
                ? null
                : (id) => run(() async {
                    setState(() {
                      connection = id;
                      model = null;
                      modelOptions = [];
                      consent = false;
                      operation = newOperationId();
                    });
                    final models = await widget.repository.models(id!);
                    if (mounted) setState(() => modelOptions = models);
                  }),
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey('$connection:$model'),
            initialValue: model,
            decoration: const InputDecoration(
              labelText: 'Modelo del proveedor; disponibilidad según tu cuenta',
            ),
            items: [
              for (final m in modelOptions)
                DropdownMenuItem(
                  value: m['id'] as String,
                  child: Text(
                    m['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: working
                ? null
                : (v) => setState(() {
                    model = v;
                    consent = false;
                    operation = newOperationId();
                  }),
          ),
          CheckboxListTile(
            value: personal,
            onChanged: working
                ? null
                : (v) => setState(() {
                    personal = v ?? false;
                    consent = false;
                    operation = newOperationId();
                  }),
            title: const Text('Usar mis chats marcados para contexto personal'),
          ),
          if (!widget.member.isPersonal)
            CheckboxListTile(
              value: team,
              onChanged: working
                  ? null
                  : (v) => setState(() {
                      team = v ?? false;
                      consent = false;
                      operation = newOperationId();
                    }),
              title: const Text(
                'Usar chats compartidos autorizados para mi rol',
              ),
            ),
          const Text(
            'Se usan extractos recientes y limitados; el chat actual conserva su continuidad. No se adjuntan expedientes automáticamente.',
          ),
          TextField(
            controller: composer,
            maxLength: 12000,
            maxLines: 4,
            enabled: !working,
            decoration: const InputDecoration(labelText: 'Mensaje'),
            onChanged: (_) => setState(() {
              consent = false;
              operation = newOperationId();
            }),
          ),
          CheckboxListTile(
            value: consent,
            onChanged: working
                ? null
                : (v) => setState(() => consent = v ?? false),
            title: const Text(
              'Autorizo enviar este mensaje y el contexto elegido al proveedor seleccionado.',
            ),
          ),
          FilledButton(
            onPressed:
                working ||
                    vm.busy ||
                    !consent ||
                    connection == null ||
                    model == null ||
                    composer.text.trim().isEmpty
                ? null
                : () => run(() async {
                    await widget.repository.send(
                      vm.selected!,
                      connection!,
                      model!,
                      composer.text.trim(),
                      operation,
                      personal,
                      team,
                    );
                    composer.clear();
                    consent = false;
                    operation = newOperationId();
                    await vm.load();
                  }),
            child: const Text('Solicitar respuesta'),
          ),
        ],
      ],
      ],
    ),
  );
}
