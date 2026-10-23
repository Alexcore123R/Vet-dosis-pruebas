import '../../../core/widgets/neu_identity.dart';
import '../../permissions/domain/permission_repository.dart';
import '../../permissions/presentation/permission_screen.dart';
import '../domain/auth_repository.dart';
import 'team_screen.dart';
import '../../welcome/presentation/product_screen.dart';
import 'package:flutter/material.dart';
import '../domain/clinic_membership.dart';
import 'auth_view_model.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.model, this.configured = true});
  final AuthViewModel? model;
  final bool configured;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _clinic = TextEditingController();
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _register = false;
  bool _reset = false;
  bool _showPassword = false;
  @override
  void dispose() {
    for (final field in [_email, _password, _clinic, _code]) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 16),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 16),
                const VetDosisBrand(large: true),
                const SizedBox(height: 36),
                if (!widget.configured || model?.signedIn == true)
                  Text(
                    model?.signedIn == true ? 'Tu clínica' : 'Bienvenido',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                const SizedBox(height: 12),
                if (!widget.configured) ...[
                  const Text(
                    'El acceso estará disponible cuando conectemos tu clínica.',
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Conexión pendiente. Tus datos aún no se envían a ningún servidor.',
                  ),
                ] else if (model!.recoveringPassword) ...[
                  const Text('Elige una nueva contraseña.'),
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          enabled: !model.busy,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'Nueva contraseña',
                          ),
                          validator: (value) => (value?.length ?? 0) >= 8
                              ? null
                              : 'Usa al menos 8 caracteres',
                        ),
                        TextFormField(
                          obscureText: true,
                          enabled: !model.busy,
                          decoration: const InputDecoration(
                            labelText: 'Confirma la contraseña',
                          ),
                          validator: (value) => value == _password.text
                              ? null
                              : 'Las contraseñas no coinciden',
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: model.busy
                        ? null
                        : () {
                            if (_form.currentState!.validate()) {
                              model.completePasswordRecovery(_password.text);
                            }
                          },
                    child: const Text('Actualizar contraseña'),
                  ),
                  TextButton(
                    onPressed: model.busy ? null : model.signOut,
                    child: const Text('Cancelar y cerrar sesión'),
                  ),
                ] else if (model.loadingMemberships) ...[
                  const Center(child: CircularProgressIndicator()),
                ] else if (!model.signedIn) ...[
                  const SizedBox(height: 24),
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                          ),
                          validator: (value) =>
                              value != null &&
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value.trim())
                              ? null
                              : 'Ingresa un correo válido',
                        ),
                        const SizedBox(height: 16),
                        if (!_reset)
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Ocultar contraseña'
                                    : 'Mostrar contraseña',
                                onPressed: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                (value?.length ?? 0) >= (_register ? 8 : 1)
                                ? null
                                : 'Revisa la contraseña (mínimo 8 caracteres al registrarte)',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  NeuPrimaryButton(
                    onPressed: model.busy
                        ? null
                        : () {
                            if (!_form.currentState!.validate()) return;
                            if (_reset) {
                              model.requestPasswordRecovery(_email.text);
                            } else if (_register) {
                              model.register(_email.text, _password.text);
                            } else {
                              model.signIn(_email.text, _password.text);
                            }
                          },
                    child: Text(
                      _reset
                          ? 'Enviar enlace de recuperación'
                          : _register
                          ? 'Crear cuenta'
                          : 'Iniciar sesión',
                    ),
                  ),
                  if (!_reset && model.googleEnabled)
                    OutlinedButton(
                      onPressed: model.busy ? null : model.googleSignIn,
                      child: const Text('Continuar con Google'),
                    ),
                  TextButton(
                    onPressed: model.busy
                        ? null
                        : () => setState(() {
                            if (_reset) {
                              _reset = false;
                            } else {
                              _register = !_register;
                            }
                            _password.clear();
                          }),
                    child: Text(
                      _reset
                          ? 'Volver al ingreso'
                          : _register
                          ? 'Ya tengo cuenta'
                          : 'Crear una cuenta',
                    ),
                  ),
                  if (!_reset && model.recoveryAvailable)
                    TextButton(
                      onPressed: model.busy
                          ? null
                          : () => setState(() {
                              _reset = true;
                              _register = false;
                              _password.clear();
                            }),
                      child: const Text('Olvidé mi contraseña'),
                    ),
                ] else ...[
                  if (model.error == null) ...[
                    if (model.personalAvailable)
                      FilledButton.icon(
                        onPressed: model.busy
                            ? null
                            : model.createPersonalWorkspace,
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Usar mi espacio personal'),
                      ),
                    const Text(
                      'Crea una clínica o ingresa el código que te compartió su administrador.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _clinic,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la nueva clínica',
                      ),
                    ),
                    FilledButton(
                      onPressed: model.busy
                          ? null
                          : () {
                              if (_clinic.text.trim().length >= 2 &&
                                  _clinic.text.trim().length <= 120) {
                                model.createClinic(_clinic.text);
                              }
                            },
                      child: const Text('Crear clínica'),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _code,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Código de invitación',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: model.busy
                          ? null
                          : () {
                              if (_code.text.trim().isNotEmpty) {
                                model.joinClinic(_code.text);
                              }
                            },
                      child: const Text('Unirme a una clínica'),
                    ),
                  ],
                  TextButton(
                    onPressed: model.busy ? null : model.refresh,
                    child: const Text('Volver a verificar acceso'),
                  ),
                  TextButton(
                    onPressed: model.busy ? null : model.signOut,
                    child: const Text('Cerrar sesión'),
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Conoce VetDosis Pro'),
                        ),
                        body: const SingleChildScrollView(
                          padding: EdgeInsets.all(20),
                          child: ProductScreen(),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Herramientas, planes y costos'),
                ),
                if (model?.busy == true)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (model?.error != null)
                  Text(
                    model!.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (model?.message != null) Text(model!.message!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClinicAccountScreen extends StatefulWidget {
  const ClinicAccountScreen({
    super.key,
    required this.model,
    this.identityBuilder,
  });
  final Widget Function(BuildContext context)? identityBuilder;
  final AuthViewModel model;
  @override
  State<ClinicAccountScreen> createState() => _ClinicAccountScreenState();
}

class _ClinicAccountScreenState extends State<ClinicAccountScreen> {
  final _email = TextEditingController();
  final _clinicName = TextEditingController();
  final _inviteCode = TextEditingController();
  ClinicRole _role = ClinicRole.mvz;
  @override
  void dispose() {
    _email.dispose();
    _clinicName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      return Scaffold(
        appBar: AppBar(title: const Text('Mi cuenta y clínicas')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.identityBuilder != null)
              widget.identityBuilder!(context),
            if (model.personalAvailable)
              TextButton.icon(
                onPressed: model.busy ? null : model.createPersonalWorkspace,
                icon: const Icon(Icons.person_outline),
                label: const Text('Abrir mi espacio personal'),
              ),
            for (final member in model.memberships)
              ListTile(
                title: Text(member.clinicName),
                subtitle: Text(
                  member.isPersonal ? 'Espacio personal' : member.role.label,
                ),
                trailing: model.active == member
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap: model.busy ? null : () => model.selectClinic(member),
              ),
            if (!model.offline &&
                model.active != null &&
                model.repository is PermissionRepository)
              OutlinedButton.icon(
                onPressed: model.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PermissionScreen(
                            model: model,
                            clinic: model.active!,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Permisos y habilitación'),
              ),
            if (!model.offline &&
                model.active?.role == ClinicRole.admin &&
                model.active?.isPersonal != true) ...[
              const Divider(),
              if (model.repository is TeamRepository &&
                  (model.repository as TeamRepository).teamManagementAvailable)
                OutlinedButton.icon(
                  onPressed: model.busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TeamScreen(model: model, clinic: model.active!),
                          ),
                        ),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Administrar equipo e invitaciones'),
                ),
              const Text('Invitar a una persona a esta clínica'),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo de la persona invitada',
                ),
              ),
              DropdownButtonFormField<ClinicRole>(
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Rol que le asignarás',
                ),
                items: ClinicRole.values
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                    )
                    .toList(),
                onChanged: (role) {
                  if (role != null) setState(() => _role = role);
                },
              ),
              FilledButton(
                onPressed: model.busy
                    ? null
                    : () {
                        if (RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(_email.text.trim())) {
                          model.invite(_email.text, _role);
                        }
                      },
                child: const Text('Generar código de invitación'),
              ),
              if (model.invitation != null) ...[
                const Text(
                  'Comparte este código con la persona invitada. Vence en 7 días y solo puede usarse una vez con su correo confirmado.',
                ),
                SelectableText(model.invitation!),
              ],
            ],
            const Divider(),
            if (!model.offline)
              ExpansionTile(
                title: const Text('Agregar otra clínica'),
                children: [
                  TextField(
                    controller: _clinicName,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la nueva clínica',
                    ),
                  ),
                  FilledButton(
                    onPressed: model.busy
                        ? null
                        : () {
                            final name = _clinicName.text.trim();
                            if (name.length >= 2 && name.length <= 120) {
                              model.createClinic(name);
                            }
                          },
                    child: const Text('Crear clínica'),
                  ),
                  TextField(
                    controller: _inviteCode,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Código de invitación',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: model.busy
                        ? null
                        : () {
                            if (_inviteCode.text.trim().isNotEmpty) {
                              model.joinClinic(_inviteCode.text);
                            }
                          },
                    child: const Text('Unirme a una clínica'),
                  ),
                ],
              ),
            TextButton(
              onPressed: model.busy ? null : model.refresh,
              child: const Text('Actualizar mis permisos'),
            ),
            if (model.error != null) Text(model.error!),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: model.busy
                  ? null
                  : () async {
                      await model.signOut();
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
    },
  );
}
