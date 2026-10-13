import '../modules/core/domain/navigation_access.dart';
import '../modules/inventory/presentation/quick_scan_screen.dart';
import '../modules/support/domain/support_repository.dart';
import '../modules/support/presentation/support_screen.dart';
import '../modules/welcome/presentation/product_screen.dart';
import '../modules/welcome/presentation/guided_start_screen.dart';
import '../modules/ai/domain/ai_repository.dart';
import '../modules/ai/presentation/ai_screen.dart';
import '../modules/subscriptions/domain/subscription_repository.dart';
import '../modules/subscriptions/presentation/subscription_screen.dart';
import '../modules/operations/domain/operations_repository.dart';
import '../modules/operations/presentation/operations_screen.dart';
import '../modules/attendance/domain/attendance_repository.dart';
import '../modules/attendance/presentation/attendance_screen.dart';
import '../modules/backup/domain/backup_repository.dart';
import '../modules/backup/presentation/backup_screen.dart';
import '../modules/inventory/domain/inventory_repository.dart';
import '../modules/inventory/presentation/inventory_screen.dart';
import '../modules/calculations/presentation/calculation_screen.dart';
import '../modules/prescribing/domain/prescribing_repository.dart';
import '../modules/prescribing/presentation/prescribing_screen.dart';
import '../modules/forms/clinical/clinical_repository.dart';
import '../modules/forms/clinical/clinical_screen.dart';
import '../modules/forms/domain/form_repository.dart';
import '../modules/forms/presentation/forms_screen.dart';
import '../modules/hospital/domain/hospital_repository.dart';
import '../modules/hospital/application/hospital_alerts.dart';
import '../modules/hospital/presentation/hospital_screen.dart';
import '../modules/patients/domain/patient_repository.dart';
import '../modules/patients/presentation/patients_screen.dart';
import 'package:flutter/material.dart';
import '../modules/doses/presentation/dose_screen.dart';
import '../modules/doses/data/personal_dose_repository.dart';
import '../modules/auth/domain/clinic_membership.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../modules/core/presentation/core_view_model.dart';
import '../modules/auth/presentation/auth_view_model.dart';
import '../modules/auth/presentation/auth_screen.dart';

const paletteNames = ['Esmeralda', 'Océano', 'Índigo', 'Ámbar', 'Obsidiana'];
const paletteColors = [
  Color(0xFF087F68),
  Color(0xFF126AAB),
  Color(0xFF6254AE),
  Color(0xFF946000),
  Color(0xFF52606D),
];

class VetDosisApp extends StatelessWidget {
  const VetDosisApp({
    super.key,
    required this.model,
    this.auth,
    this.requireAuth = false,
    this.personalDoses,
    this.patients,
    this.hospital,
    this.hospitalAlerts,
    this.forms,
    this.clinical,
    this.prescribing,
    this.inventory,
    this.operations,
    this.attendance,
    this.backup,
    this.ai,
    this.subscriptions,
    this.support,
  });
  final CoreViewModel model;
  final AuthViewModel? auth;
  final bool requireAuth;
  final PersonalDoseRepository? personalDoses;
  final PatientRepository? patients;
  final HospitalRepository? hospital;
  final HospitalAlerts? hospitalAlerts;
  final FormRepository? forms;
  final ClinicalRepository? clinical;
  final PrescribingRepository? prescribing;
  final InventoryRepository? inventory;
  final OperationsRepository? operations;
  final AttendanceRepository? attendance;
  final BackupRepository? backup;
  final AiRepository? ai;
  final SubscriptionRepository? subscriptions;
  final SupportRepository? support;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: paletteColors[model.settings.palette],
        brightness: brightness,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xFF20272D)
          : const Color(0xFFEDF2F4),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, ?auth]),
    builder: (context, _) => MaterialApp(
      key: ValueKey(
        '${auth?.active?.userId}:${auth?.active?.clinicId}:${auth?.active?.role.name}:${auth?.signedIn}',
      ),
      title: 'VetDosis Pro',
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: model.themeMode,
      home:
          requireAuth &&
              (auth == null ||
                  auth!.loadingMemberships ||
                  !auth!.signedIn ||
                  auth!.recoveringPassword ||
                  auth!.active == null)
          ? AuthScreen(model: auth, configured: auth != null)
          : CoreShell(
              model: model,
              auth: auth,
              personalDoses: personalDoses,
              patients: patients,
              hospital: hospital,
              hospitalAlerts: hospitalAlerts,
              forms: forms,
              clinical: clinical,
              prescribing: prescribing,
              inventory: inventory,
              operations: operations,
              attendance: attendance,
              backup: backup,
              ai: ai,
              subscriptions: subscriptions,
              support: support,
            ),
    ),
  );
}

class CoreShell extends StatelessWidget {
  const CoreShell({
    super.key,
    required this.model,
    this.auth,
    this.personalDoses,
    this.patients,
    this.hospital,
    this.hospitalAlerts,
    this.forms,
    this.clinical,
    this.prescribing,
    this.inventory,
    this.operations,
    this.attendance,
    this.backup,
    this.ai,
    this.subscriptions,
    this.support,
  });
  final CoreViewModel model;
  final AuthViewModel? auth;
  final PersonalDoseRepository? personalDoses;
  final PatientRepository? patients;
  final HospitalRepository? hospital;
  final HospitalAlerts? hospitalAlerts;
  final FormRepository? forms;
  final ClinicalRepository? clinical;
  final PrescribingRepository? prescribing;
  final InventoryRepository? inventory;
  final OperationsRepository? operations;
  final AttendanceRepository? attendance;
  final BackupRepository? backup;
  final AiRepository? ai;
  final SubscriptionRepository? subscriptions;
  final SupportRepository? support;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: model.screen == 'Inicio',
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) model.navigate('Inicio');
    },
    child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.screen == 'Inicio' ? 'VetDosis Pro' : model.screen,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (auth?.active != null)
              Text(
                auth!.active!.clinicName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: [
          if (auth != null)
            IconButton(
              tooltip: 'Mi cuenta y clínicas',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ClinicAccountScreen(model: auth!),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => model.navigate('Ajustes'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('VetDosis Pro'),
                subtitle: Text('Tu espacio veterinario'),
              ),
              for (final branch in ClinicalBranch.values)
                ListTile(
                  leading: Icon(branch.icon),
                  title: Text(branch.label),
                  selected: model.branch == branch,
                  onTap: () {
                    model.selectBranch(branch);
                    Navigator.pop(context);
                  },
                ),
              const Divider(),
              for (final page in [
                'Inicio',
                'Cálculo rápido',
                'Escanear producto',
                'Hospitalización',
                'Cálculos clínicos',
                'Pacientes',
                'Formatos',
                'Receta',
                'Agenda',
                if (auth?.active?.isPersonal != true) 'Checado',
                'Asistente IA',
                'Planes',
                'Producto y costos',
                'Inicio guiado',
                'Ayuda y soporte',
                'Estadísticas y respaldo',
                'Inventario',
                'Ajustes',
              ])
                if (navigationAllowed(page, auth?.active))
                  ListTile(
                    title: Text(page),
                    selected: model.screen == page,
                    onTap: () {
                      model.navigate(page);
                      Navigator.pop(context);
                    },
                  ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (auth?.offline == true) ...[
                  const SoftPanel(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Sin conexión · Acceso guardado. La gestión del equipo requiere conexión.',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => auth!.refresh(),
                    child: const Text('Reintentar conexión'),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<ClinicalBranch>(
                  initialValue: model.branch,
                  key: ValueKey(model.branch),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rama de trabajo',
                    border: OutlineInputBorder(),
                  ),
                  items: ClinicalBranch.values
                      .map(
                        (branch) => DropdownMenuItem(
                          value: branch,
                          child: Text(
                            branch.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (branch) {
                    if (branch != null) model.selectBranch(branch);
                  },
                ),
                const SizedBox(height: 28),
                if (model.screen == 'Inicio')
                  ...home(context)
                else if (model.screen == 'Cálculo rápido')
                  auth == null ||
                          [
                            ClinicRole.admin,
                            ClinicRole.mvz,
                          ].contains(auth!.active?.role)
                      ? DoseScreen(
                          key: ValueKey(
                            '${auth?.active?.userId}:${auth?.active?.clinicId}',
                          ),
                          personalRepository: personalDoses,
                          clinicId: auth?.active?.clinicId,
                          userId: auth?.active?.userId,
                          admin: auth?.active?.role == ClinicRole.admin,
                          offline: auth?.offline ?? false,
                        )
                      : const Text(
                          'El cálculo clínico requiere acceso de MVZ o administrador.',
                        )
                else if (model.screen == 'Cálculos clínicos')
                  auth == null ||
                          [
                            ClinicRole.admin,
                            ClinicRole.mvz,
                          ].contains(auth!.active?.role)
                      ? CalculationScreen(
                          showAviculture:
                              model.branch == ClinicalBranch.production,
                          key: ValueKey(model.branch),
                          initialTool: model.branch == ClinicalBranch.exotic
                              ? 'metabolic'
                              : model.branch == ClinicalBranch.production
                              ? 'water'
                              : 'fluids',
                        )
                      : const Text(
                          'Los cálculos clínicos requieren acceso de MVZ o administrador.',
                        )
                else if (model.screen == 'Pacientes')
                  patients != null && auth?.active != null
                      ? auth!.offline
                            ? const Text(
                                'Los expedientes requieren conexión por ahora. Reconecta para consultar o guardar datos.',
                              )
                            : PatientsScreen(
                                key: ValueKey(
                                  '${auth!.active!.userId}:${auth!.active!.clinicId}:${auth!.active!.role.name}',
                                ),
                                repository: patients!,
                                member: auth!.active!,
                                onOpenClinical:
                                    clinical != null && forms != null
                                    ? (patient) async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => ClinicalScreen(
                                              repository: clinical!,
                                              prescribing: prescribing,
                                              forms: forms!,
                                              member: auth!.active!,
                                              patientId: patient.id,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir pacientes.',
                        )
                else if (model.screen == 'Hospitalización')
                  hospital != null &&
                          patients != null &&
                          hospitalAlerts != null &&
                          auth?.active != null
                      ? ![
                              ClinicRole.admin,
                              ClinicRole.mvz,
                              ClinicRole.auxiliar,
                            ].contains(auth!.active!.role)
                            ? const Text(
                                'Hospitalización requiere acceso clínico de MVZ, admin o auxiliar.',
                              )
                            : auth!.offline
                            ? const Text(
                                'Reconecta para consultar o registrar tratamientos. Los avisos locales ya programados pueden continuar; comprueba el estado actual antes de administrar.',
                              )
                            : HospitalScreen(
                                key: ValueKey(
                                  '${auth!.active!.userId}:${auth!.active!.clinicId}:${auth!.active!.role.name}',
                                ),
                                repository: hospital!,
                                patients: patients!,
                                member: auth!.active!,
                                alerts: hospitalAlerts!,
                                onRecordMedication:
                                    prescribing != null &&
                                        clinical != null &&
                                        forms != null
                                    ? (task) async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => Scaffold(
                                              appBar: AppBar(
                                                title: const Text(
                                                  'Registrar medicación',
                                                ),
                                              ),
                                              body: SingleChildScrollView(
                                                padding: const EdgeInsets.all(
                                                  20,
                                                ),
                                                child: PrescribingScreen(
                                                  repository: prescribing!,
                                                  clinical: clinical!,
                                                  forms: forms!,
                                                  member: auth!.active!,
                                                  initialCase:
                                                      task.clinicalCaseId,
                                                  initialTask: task.id,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir hospitalización.',
                        )
                else if (model.screen == 'Receta')
                  prescribing != null &&
                          clinical != null &&
                          forms != null &&
                          auth?.active != null
                      ? auth!.offline
                            ? const Text(
                                'Reconecta para consultar perfiles, recetas y medicamentos.',
                              )
                            : ![
                                ClinicRole.admin,
                                ClinicRole.mvz,
                                ClinicRole.auxiliar,
                              ].contains(auth!.active!.role)
                            ? const Text('Este módulo requiere acceso clínico.')
                            : PrescribingScreen(
                                repository: prescribing!,
                                clinical: clinical!,
                                forms: forms!,
                                member: auth!.active!,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir recetas.',
                        )
                else if (model.screen == 'Formatos')
                  forms != null && patients != null && auth?.active != null
                      ? auth!.offline
                            ? const Text(
                                'Los formatos y las firmas requieren conexión. No se guardan documentos sensibles offline.',
                              )
                            : FormsScreen(
                                repository: forms!,
                                clinical: clinical,
                                prescribing: prescribing,
                                patients: patients!,
                                member: auth!.active!,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir formatos.',
                        )
                else if (model.screen == 'Escanear producto')
                  inventory != null &&
                          auth?.active != null &&
                          auth?.offline != true &&
                          navigationAllowed('Escanear producto', auth?.active)
                      ? QuickScanScreen(
                          repository: inventory!,
                          member: auth!.active!,
                        )
                      : const Text(
                          'Conecta tu cuenta y verifica el acceso a inventario para escanear productos.',
                        )
                else if (model.screen == 'Inventario')
                  inventory != null && auth?.active != null
                      ? auth!.offline
                            ? const Text(
                                'Inventario, ventas y caja requieren conexión para confirmar saldos y permisos.',
                              )
                            : auth!.active!.role == ClinicRole.estilista
                            ? const Text(
                                'Inventario y caja requieren permiso operativo de la clínica.',
                              )
                            : InventoryScreen(
                                repository: inventory!,
                                member: auth!.active!,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir inventario.',
                        )
                else if (model.screen == 'Agenda')
                  operations != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? OperationsScreen(
                          repository: operations!,
                          member: auth!.active!,
                          onOpenPatient:
                              patients != null &&
                                  auth!.active!.role != ClinicRole.estilista
                              ? (id) async {
                                  final member = auth!.active!;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Scaffold(
                                        appBar: AppBar(
                                          title: const Text(
                                            'Paciente de la cita',
                                          ),
                                        ),
                                        body: SingleChildScrollView(
                                          padding: const EdgeInsets.all(20),
                                          child: PatientsScreen(
                                            repository: patients!,
                                            member: member,
                                            initialPatientId: id,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir operación y agenda.',
                        )
                else if (model.screen == 'Checado')
                  attendance != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? AttendanceScreen(
                          repository: attendance!,
                          member: auth!.active!,
                        )
                      : const Text(
                          'El checado requiere conexión con el servidor.',
                        )
                else if (model.screen == 'Estadísticas y respaldo')
                  backup != null &&
                          auth?.active?.role == ClinicRole.admin &&
                          auth?.offline != true
                      ? BackupScreen(repository: backup!, member: auth!.active!)
                      : const Text(
                          'Las estadísticas y el respaldo requieren conexión y acceso admin de la clínica.',
                        )
                else if (model.screen == 'Asistente IA')
                  ai != null && auth?.active != null && auth?.offline != true
                      ? AiScreen(repository: ai!, member: auth!.active!)
                      : const Text('El asistente requiere cuenta y conexión.')
                else if (model.screen == 'Planes')
                  subscriptions != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? SubscriptionScreen(
                          repository: subscriptions!,
                          member: auth!.active!,
                        )
                      : const Text('Los planes requieren cuenta y conexión.')
                else if (model.screen == 'Producto y costos')
                  ProductScreen(onNavigate: model.navigate)
                else if (model.screen == 'Inicio guiado')
                  GuidedStartScreen(
                    scope: '${auth?.active?.userId}:${auth?.active?.clinicId}',
                    onNavigate: (page) {
                      if (page == 'Mi cuenta' && auth != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AuthScreen(model: auth),
                          ),
                        );
                      } else {
                        model.navigate(page);
                      }
                    },
                  )
                else if (model.screen == 'Ayuda y soporte')
                  support != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? SupportScreen(
                          repository: support!,
                          member: auth!.active!,
                          onAi: ai == null
                              ? null
                              : (draft) async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Scaffold(
                                        appBar: AppBar(
                                          title: const Text('Ayuda con IA'),
                                        ),
                                        body: SingleChildScrollView(
                                          padding: const EdgeInsets.all(16),
                                          child: AiScreen(
                                            repository: ai!,
                                            member: auth!.active!,
                                            initialDraft: draft,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                        )
                      : const Text(
                          'El soporte requiere cuenta y conexión. Puedes consultar Producto y costos o Inicio guiado sin enviar datos.',
                        )
                else if (model.screen == 'Ajustes')
                  ...settings(context)
                else
                  ...pending(context),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> home(BuildContext context) => [
    Text(
      'Todo comienza con un buen cuidado.',
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => model.navigate('Inicio guiado'),
          child: const Text('Primeros pasos'),
        ),
        TextButton(
          onPressed: () => model.navigate('Producto y costos'),
          child: const Text('Conoce VetDosis Pro'),
        ),
        TextButton(
          onPressed: () => model.navigate('Ayuda y soporte'),
          child: const Text('Ayuda y contacto'),
        ),
      ],
    ),
    Text(model.branch.label, style: Theme.of(context).textTheme.titleMedium),
    const Text(
      'La rama organiza accesos. Confirma especie, paciente y presentación en cada cálculo.',
    ),
    if (navigationAllowed('Cálculos clínicos', auth?.active))
      TextButton.icon(
        onPressed: () => model.navigate('Cálculos clínicos'),
        icon: Icon(model.branch.icon),
        label: Text(switch (model.branch) {
          ClinicalBranch.exotic => 'Peso metabólico y referencias de exóticos',
          ClinicalBranch.production =>
            'Agua, alimento y cálculos de producción',
          ClinicalBranch.management => 'Abrir cálculos clínicos',
          ClinicalBranch.small => 'Fluidoterapia, CRI y referencias clínicas',
        }),
      ),
    if (model.branch == ClinicalBranch.management)
      Wrap(
        spacing: 8,
        children: [
          for (final p in ['Agenda', 'Inventario', 'Estadísticas y respaldo'])
            if (navigationAllowed(p, auth?.active))
              TextButton(onPressed: () => model.navigate(p), child: Text(p)),
        ],
      ),
    const SizedBox(height: 24),
    LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700
            ? 4
            : constraints.maxWidth >= 330 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.2
            ? 2
            : 1;
        final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final action in <(String, IconData, String)>[
              (
                'Cálculo rápido',
                Icons.calculate_outlined,
                'Por paciente y presentación',
              ),
              (
                'Escanear producto',
                Icons.qr_code_scanner,
                'Cámara y código de barras',
              ),
              ('Receta', Icons.description_outlined, 'Indicaciones y PDF'),
              (
                'Hospitalización',
                Icons.local_hospital_outlined,
                'Hoja de tratamientos',
              ),
            ])
              if (navigationAllowed(action.$1, auth?.active))
                SizedBox(
                  width: width,
                  child: SoftPanel(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => model.navigate(action.$1),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              action.$2,
                              size: 32,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              action.$1,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(action.$3),
                            const SizedBox(height: 12),
                            const Text('Abrir'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    ),
    const SizedBox(height: 16),
    FirstStepsBanner(
      key: ValueKey('guide:${auth?.active?.userId}:${auth?.active?.clinicId}'),
      scope: '${auth?.active?.userId}:${auth?.active?.clinicId}',
      onOpen: () => model.navigate('Inicio guiado'),
    ),
    const SizedBox(height: 28),
    SoftPanel(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(auth?.active?.clinicName ?? 'Estamos preparando tu clínica'),
            const SizedBox(height: 8),
            Text(
              auth?.active != null
                  ? 'Tu rol en esta clínica: ${auth!.active!.role.label}'
                  : 'El acceso a tu clínica estará disponible al conectar tu cuenta.',
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> settings(BuildContext context) => [
    Text('Ajustes', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 24),
    Text('Elige tu tema', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var index = 0; index < paletteNames.length; index++)
          ChoiceChip(
            label: Text(paletteNames[index]),
            avatar: CircleAvatar(
              backgroundColor: paletteColors[index],
              radius: 8,
            ),
            selected: model.settings.palette == index,
            onSelected: (_) => model.updateSettings(palette: index),
          ),
      ],
    ),
    const SizedBox(height: 24),
    DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: model.settings.brightness,
      key: ValueKey(model.settings.brightness),
      decoration: const InputDecoration(
        labelText: 'Apariencia',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'system', child: Text('Seguir al dispositivo')),
        DropdownMenuItem(value: 'light', child: Text('Claro')),
        DropdownMenuItem(value: 'dark', child: Text('Oscuro')),
      ],
      onChanged: (value) {
        if (value != null) model.updateSettings(brightness: value);
      },
    ),
    if (model.saveError != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          model.saveError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    const SizedBox(height: 24),
    const Divider(),
    Text('Cuenta y espacio', style: Theme.of(context).textTheme.titleLarge),
    if (auth != null)
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: const Text('Mi cuenta y clínicas'),
        subtitle: const Text('Espacio personal, clínica e invitaciones'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => AuthScreen(model: auth)),
        ),
      ),
    Text(
      'Configura tus herramientas',
      style: Theme.of(context).textTheme.titleLarge,
    ),
    for (final option in <(String, String, String)>[
      (
        'Perfil profesional, firma y permisos',
        'Revisa tus datos antes de emitir documentos.',
        'Receta',
      ),
      (
        'Membrete y plantillas',
        'Logo, versiones y formatos de tu clínica.',
        'Formatos',
      ),
      (
        'Avisos de hospitalización',
        'Activa y revisa permisos en la hoja de tratamientos.',
        'Hospitalización',
      ),
      (
        'Inventario, ventas y pagos de clientes',
        'Productos, caja y referencias de cobro.',
        'Inventario',
      ),
      (
        'Proveedor de IA y privacidad',
        'Claves, modelos y uso de contexto.',
        'Asistente IA',
      ),
      (
        'Plan y pagos de VetDosis',
        'Suscripción y beneficios de tu espacio.',
        'Planes',
      ),
      (
        'Exportación y respaldo',
        'Consulta límites y genera tus archivos.',
        'Estadísticas y respaldo',
      ),
      (
        'Ayuda y contacto',
        'Reportes, archivos y seguimiento.',
        'Ayuda y soporte',
      ),
      ('Primeros pasos', 'Retoma la guía de configuración.', 'Inicio guiado'),
    ])
      if (navigationAllowed(option.$3, auth?.active))
        ListTile(
          title: Text(option.$1),
          subtitle: Text(option.$2),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => model.navigate(option.$3),
        ),
    const Text('VetDosis Pro · Versión de pruebas · 0.1.0'),
  ];

  List<Widget> pending(BuildContext context) => [
    Text(model.screen, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 24),
    const SoftPanel(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Este módulo está pendiente de implementar.'),
      ),
    ),
    const SizedBox(height: 24),
    Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => model.navigate('Inicio'),
        icon: const Icon(Icons.home_outlined),
        label: const Text('Volver al inicio'),
      ),
    ),
  ];
}

class SoftPanel extends StatelessWidget {
  const SoftPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x55000000) : const Color(0xFFD0D8DC),
            offset: const Offset(6, 6),
            blurRadius: 14,
          ),
          BoxShadow(
            color: dark ? const Color(0xFF2A333B) : Colors.white,
            offset: const Offset(-6, -6),
            blurRadius: 14,
          ),
        ],
      ),
      child: child,
    );
  }
}
