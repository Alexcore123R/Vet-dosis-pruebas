import 'package:flutter/material.dart';

Future<String?> requestBackupPassword(
  BuildContext context, {
  required bool creating,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BackupPasswordDialog(creating: creating),
);

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.creating});
  final bool creating;
  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.creating ? 'Proteger respaldo' : 'Abrir respaldo protegido',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.creating
                  ? 'Guarda esta contraseña fuera de la app. No la almacenamos y no podemos recuperarla si la pierdes.'
                  : 'La contraseña se utiliza en este dispositivo para abrir el archivo.',
            ),
            TextFormField(
              controller: password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Contraseña del respaldo',
              ),
              validator: (v) =>
                  v == null ||
                      v.length > 1024 ||
                      (widget.creating ? v.trim().length < 12 : v.isEmpty)
                  ? (widget.creating
                        ? 'Usa al menos 12 caracteres'
                        : 'Ingresa la contraseña')
                  : null,
            ),
            if (widget.creating)
              TextFormField(
                controller: confirmation,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirma la contraseña',
                ),
                validator: (v) =>
                    v == password.text ? null : 'Las contraseñas no coinciden',
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, password.text);
          }
        },
        child: Text(widget.creating ? 'Proteger' : 'Abrir'),
      ),
    ],
  );
}
