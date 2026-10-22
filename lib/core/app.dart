import 'dart:math' as math;
import 'widgets/app_version_label.dart';
import '../modules/finance/presentation/financial_planning_panel.dart';
import '../modules/operations/presentation/productivity_screen.dart';
import '../modules/core/presentation/section_menu.dart';
import '../modules/production/presentation/production_menu.dart';
import '../modules/dashboard/presentation/home_pilot.dart';
import '../vet_ui/vet_theme.dart';
import '../modules/beta/domain/beta_repository.dart';
import '../modules/beta/presentation/beta_boundary.dart';
import '../modules/identity/domain/identity_repository.dart';
import '../modules/identity/presentation/identity_panel.dart';
import '../modules/dashboard/presentation/alert_preferences_panel.dart';
import 'widgets/workspace_panel.dart';
import '../modules/dashboard/presentation/dashboard_screen.dart';
import '../modules/dashboard/presentation/dashboard_view_model.dart';
import '../modules/core/domain/navigation_access.dart';
import '../modules/core/domain/module_access.dart';
import '../modules/core/presentation/module_access_boundary.dart';
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
import '../modules/operations/presentation/contact_directory_screen.dart';
import '../modules/operations/presentation/promotions_screen.dart';
import '../modules/operations/presentation/commission_panel.dart';
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
import '../modules/doses/presentation/dose_math_tools.dart';
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
    this.beta,
    this.personalDoses,
    this.patients,
    this.hospital,
    this.hospitalAlerts,
    this.forms,
    this.identity,
    this.clinical,
    this.prescribing,
    this.inventory,
    this.operations,
    this.attendance,
    this.backup,
    this.ai,
    this.subscriptions,
    this.support,
    this.moduleAccess,
  });
  final CoreViewModel model;
  final AuthViewModel? auth;
  final bool requireAuth;
  final BetaRepository? beta;
  final PersonalDoseRepository? personalDoses;
  final PatientRepository? patients;
  final HospitalRepository? hospital;
  final HospitalAlerts? hospitalAlerts;
  final FormRepository? forms;
  final IdentityRepository? identity;
  final ClinicalRepository? clinical;
  final PrescribingRepository? prescribing;
  final InventoryRepository? inventory;
  final OperationsRepository? operations;
  final AttendanceRepository? attendance;
  final BackupRepository? backup;
  final AiRepository? ai;
  final SubscriptionRepository? subscriptions;
  final SupportRepository? support;
  final ModuleAccessRepository? moduleAccess;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final neumorphic = model.settings.visualStyle == 'neu';
    final background = dark ? const Color(0xFF0B121C) : VetColors.canvas;
    final surface = dark ? const Color(0xFF131E2A) : VetColors.surface;
    final primary = dark ? const Color(0xFF55E2D3) : VetColors.purple;
    final secondary = dark ? const Color(0xFFB69BFF) : VetColors.turquoise;
    final tertiary = dark ? const Color(0xFFFF92C9) : VetColors.lavender;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: neumorphic
              ? primary
              : paletteColors[model.settings.palette],
          brightness: brightness,
        ).copyWith(
          primary: neumorphic ? primary : null,
          onPrimary: neumorphic
              ? (dark ? const Color(0xFF062321) : Colors.white)
              : null,
          secondary: neumorphic ? secondary : null,
          tertiary: neumorphic ? tertiary : null,
          surface: neumorphic ? surface : null,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: neumorphic ? background : null,
      inputDecorationTheme: neumorphic
          ? InputDecorationTheme(
              filled: true,
              fillColor: surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: dark
                      ? const Color(0xFF26384A)
                      : const Color(0xFFDDE7EF),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: dark
                      ? const Color(0xFF26384A)
                      : const Color(0xFFDDE7EF),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: primary, width: 1.5),
              ),
            )
          : null,
      chipTheme: neumorphic
          ? ChipThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(
                color: dark ? const Color(0xFF2A3A4B) : const Color(0xFFDDE7EF),
              ),
            )
          : null,
      navigationBarTheme: neumorphic
          ? NavigationBarThemeData(
              backgroundColor: surface,
              indicatorColor: primary.withValues(alpha: dark ? 0.22 : 0.18),
              elevation: 0,
            )
          : null,
      extensions: [WorkspaceStyle(neumorphic: neumorphic)],
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
          beta != null &&
              auth?.signedIn == true &&
              auth?.recoveringPassword != true
          ? BetaBoundary(
              key: ValueKey('beta:${auth!.repository.userId}'),
              repository: beta!,
              clinicId: auth!.active?.clinicId,
              canSponsor: auth!.active?.role == ClinicRole.admin,
              onSignOut: auth!.repository.signOut,
              onRefresh: () => auth!.refresh(),
              child: shell(context),
            )
          : shell(context),
    ),
  );

  Widget shell(BuildContext context) =>
      requireAuth &&
          (auth == null ||
              auth!.loadingMemberships ||
              !auth!.signedIn ||
              auth!.recoveringPassword ||
              auth!.active == null)
      ? AuthScreen(model: auth, configured: auth != null)
      : ModuleAccessBoundary(
          member: auth?.active,
          repository: moduleAccess,
          revision: auth?.accessRevision ?? 0,
          builder: (access) => CoreShell(
            model: model,
            auth: auth,
            moduleAccess: access,
            personalDoses: personalDoses,
            patients: patients,
            hospital: hospital,
            hospitalAlerts: hospitalAlerts,
            forms: forms,
            identity: identity,
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
    this.identity,
    this.clinical,
    this.prescribing,
    this.inventory,
    this.operations,
    this.attendance,
    this.backup,
    this.ai,
    this.subscriptions,
    this.support,
    this.moduleAccess,
  });
  final CoreViewModel model;
  final AuthViewModel? auth;
  final PersonalDoseRepository? personalDoses;
  final PatientRepository? patients;
  final HospitalRepository? hospital;
  final HospitalAlerts? hospitalAlerts;
  final FormRepository? forms;
  final IdentityRepository? identity;
  final ClinicalRepository? clinical;
  final PrescribingRepository? prescribing;
  final InventoryRepository? inventory;
  final OperationsRepository? operations;
  final AttendanceRepository? attendance;
  final BackupRepository? backup;
  final AiRepository? ai;
  final SubscriptionRepository? subscriptions;
  final SupportRepository? support;
  final ModuleAccess? moduleAccess;

  bool allowed(String page) =>
      navigationAllowed(page, auth?.active, moduleAccess);
  Future<void> openAccount(BuildContext context) async {
    if (auth == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClinicAccountScreen(
          model: auth!,
          identityBuilder: (_) => Column(
            children: [
              if (auth!.repository.userId != null)
                ProfileAppearance(
                  key: ValueKey(auth!.repository.userId),
                  userId: auth!.repository.userId!,
                  repository: identity,
                ),
              if (auth!.active != null)
                ClinicIdentity(
                  key: ValueKey(
                    '${auth!.active!.clinicId}:${auth!.active!.role}',
                  ),
                  member: auth!.active!,
                  repository: forms,
                  identity: identity,
                  editable: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget bottomNavigation() {
    final destinations = <(String, IconData)>[
      ('Inicio', Icons.home_outlined),
      if (allowed('Agenda')) ('Agenda', Icons.calendar_month_outlined),
      if (allowed('Pacientes')) ('Pacientes', Icons.pets_outlined),
      if (allowed('Cálculos')) ('Cálculos', Icons.calculate_outlined),
      ('Más', Icons.grid_view_outlined),
    ];
    final page = switch (model.screen) {
      'Cálculo rápido' ||
      'Operaciones de dosis' ||
      'Cálculos clínicos' => 'Cálculos',
      'Producción y grandes especies' => 'Inicio',
      _ => model.screen,
    };
    final selected = destinations.indexWhere((entry) => entry.$1 == page);
    return NavigationBar(
      selectedIndex: selected < 0 ? destinations.length - 1 : selected,
      onDestinationSelected: (index) => model.navigate(destinations[index].$1),
      destinations: [
        for (final entry in destinations)
          NavigationDestination(icon: Icon(entry.$2), label: entry.$1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: homePilotTheme(Theme.of(context)),
    child: Builder(builder: _buildShell),
  );

  Widget _buildShell(BuildContext context) => PopScope(
    canPop: model.screen == 'Inicio',
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) model.navigate('Inicio');
    },
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: auth?.active == null
            ? 56
            : math.max(
                68,
                (model.screen == 'Inicio'
                        ? 44.0
                        : MediaQuery.textScalerOf(context).scale(
                                Theme.of(
                                      context,
                                    ).textTheme.titleLarge?.fontSize ??
                                    22,
                              ) *
                              1.4) +
                    MediaQuery.textScalerOf(context).scale(
                          Theme.of(context).textTheme.labelSmall?.fontSize ??
                              11,
                        ) *
                        1.4 +
                    16,
              ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (model.screen == 'Inicio')
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/brand/vetdosis-logo.png',
                    width: 140,
                    height: 44,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, .3),
                    semanticLabel: 'VetDosis Pro',
                  ),
                ),
              )
            else
              Text(model.screen, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              icon: AccountAvatar(
                userId: auth!.repository.userId ?? 'signed-out',
                repository: identity,
              ),
              onPressed: () => openAccount(context),
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
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Área de trabajo'),
              ),
              for (final branch in ClinicalBranch.values.where(
                (b) => b != ClinicalBranch.management,
              ))
                ListTile(
                  leading: Icon(branch.icon),
                  title: Text(branch.label),
                  selected: model.branch == branch,
                  onTap: () {
                    Navigator.pop(context);
                    model.selectBranch(branch);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: const Text('Gestión clínica'),
                onTap: () {
                  Navigator.pop(context);
                  model.selectBranch(ClinicalBranch.management);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SectionMenu(
                  member: auth?.active,
                  access: moduleAccess,
                  onNavigate: (page) {
                    Navigator.pop(context);
                    model.navigate(page);
                  },
                  onAccount: auth == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          openAccount(context);
                        },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottomNavigation(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allowed('Escanear producto')) ...[
            FloatingActionButton.small(
              heroTag: 'scanner',
              tooltip: 'Escáner',
              onPressed: () => model.navigate('Escanear producto'),
              child: const Icon(Icons.qr_code_scanner),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.small(
            heroTag: 'assistant',
            tooltip: 'Asistente IA',
            onPressed: () => model.navigate('Asistente IA'),
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'support',
            tooltip: 'Ayuda y soporte',
            onPressed: () => model.navigate('Ayuda y soporte'),
            child: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: ListView(
              key: ValueKey((
                auth?.active?.userId,
                auth?.active?.clinicId,
                model.branch,
                model.screen,
              )),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 220),
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
                if (model.screen == 'Inicio')
                  HomePracticeSelector(
                    selected: model.branch,
                    onChanged: model.selectBranch,
                  )
                else if (![
                  'Más',
                  'Producción y grandes especies',
                ].contains(model.screen))
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
                if (auth?.active != null &&
                    moduleAccess != null &&
                    !allowed(model.screen))
                  const Text(
                    'Este apartado no está disponible con tus permisos actuales.',
                  )
                else if (model.screen == 'Inicio')
                  ...home(context)
                else if (model.screen == 'Más')
                  SectionMenu(
                    member: auth?.active,
                    access: moduleAccess,
                    initialGroup: model.branch == ClinicalBranch.management
                        ? 'Administración y finanzas'
                        : null,
                    onNavigate: model.navigate,
                    onAccount: auth == null ? null : () => openAccount(context),
                  )
                else if (model.screen == 'Planeación financiera')
                  allowed('Planeación financiera')
                      ? FinancialPlanningPanel(
                          key: ValueKey(
                            '${auth?.active?.userId}:${auth?.active?.clinicId}',
                          ),
                        )
                      : const Text(
                          'Este apartado no está disponible con tus permisos actuales.',
                        )
                else if (model.screen == 'Cálculos')
                  CalculationMenu(
                    member: auth?.active,
                    access: moduleAccess,
                    onNavigate: model.navigate,
                  )
                else if (model.screen == 'Producción y grandes especies')
                  ProductionMenu(
                    member: auth?.active,
                    access: moduleAccess,
                    onNavigate: model.navigate,
                  )
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
                else if (model.screen == 'Operaciones de dosis')
                  auth == null ||
                          [
                            ClinicRole.admin,
                            ClinicRole.mvz,
                          ].contains(auth!.active?.role)
                      ? const DoseMathTools()
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
                                ai: ai,
                                key: ValueKey(
                                  '${auth!.active!.userId}:${auth!.active!.clinicId}:${auth!.active!.role.name}',
                                ),
                                repository: patients!,
                                member: auth!.active!,
                                canOpenActivity: allowed,
                                onOpenActivity: (destination, patientId) async {
                                  if (allowed(destination)) {
                                    model.navigate(
                                      destination,
                                      patientId: patientId,
                                    );
                                  }
                                },
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
                                initialPatientId: model.activityPatientId,
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
                                                  identity: identity,
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
                                identity: identity,
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
                                ai: ai,
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
                          allowed('Escanear producto')
                      ? QuickScanScreen(
                          repository: inventory!,
                          member: auth!.active!,
                        )
                      : const Text(
                          'Conecta tu cuenta y verifica el acceso a inventario para escanear productos.',
                        )
                else if (model.screen == 'Inventario' || model.screen == 'Caja')
                  inventory != null && auth?.active != null
                      ? auth!.offline
                            ? const Text(
                                'Inventario, ventas y caja requieren conexión para confirmar saldos y permisos.',
                              )
                            : InventoryScreen(
                                identity: identity,
                                ai: ai,
                                key: ValueKey('inventory:${model.screen}'),
                                initialSection: model.screen == 'Caja'
                                    ? 'cash'
                                    : 'stock',
                                repository: inventory!,
                                member: auth!.active!,
                              )
                      : const Text(
                          'Conecta tu cuenta y clínica para abrir inventario.',
                        )
                else if (model.screen == 'Agenda telefónica')
                  operations != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? ContactDirectoryScreen(
                          embedded: true,
                          repository: operations!,
                          member: auth!.active!,
                        )
                      : const Text(
                          'El directorio de la clínica requiere cuenta y conexión.',
                        )
                else if (model.screen == 'Productividad y semana')
                  operations is ProductivityRepository &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? ProductivityScreen(
                          embedded: true,
                          repository: operations as ProductivityRepository,
                          member: auth!.active!,
                          ai: ai,
                        )
                      : const Text(
                          'La planificación semanal requiere cuenta y conexión.',
                        )
                else if (model.screen == 'Promociones')
                  operations != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? PromotionsScreen(
                          embedded: true,
                          repository: operations!,
                          member: auth!.active!,
                          ai: ai,
                        )
                      : const Text(
                          'Las promociones requieren cuenta y conexión.',
                        )
                else if (model.screen == 'Agenda' ||
                    model.screen == 'Equipo y avisos' ||
                    model.screen == 'Pendientes del equipo' ||
                    model.screen == 'Servicios' ||
                    model.screen == 'Proveedores')
                  operations != null &&
                          auth?.active != null &&
                          auth?.offline != true
                      ? OperationsScreen(
                          ai: ai,
                          key: ValueKey(
                            'operations:${model.screen}:${auth?.active?.clinicId}:${auth?.active?.userId}:${model.activityPatientId}',
                          ),
                          initialSection: model.screen == 'Servicios'
                              ? 'services'
                              : model.screen == 'Proveedores'
                              ? 'suppliers'
                              : model.screen == 'Equipo y avisos'
                              ? 'messages'
                              : model.screen == 'Pendientes del equipo'
                              ? 'tasks'
                              : 'appointments',
                          initialPatientId: model.activityPatientId,
                          onNavigate: model.navigate,
                          canOpenInventory: allowed('Inventario'),
                          canOpenSales: allowed('Caja'),
                          repository: operations!,
                          member: auth!.active!,
                          onOpenPatient:
                              patients != null && allowed('Pacientes')
                              ? (id) async {
                                  final member = auth!.active!;
                                  final patientTheme = homePilotTheme(
                                    Theme.of(context),
                                  );
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Theme(
                                        data: patientTheme,
                                        child: Scaffold(
                                          appBar: AppBar(
                                            title: const Text(
                                              'Paciente de la cita',
                                            ),
                                          ),
                                          body: SingleChildScrollView(
                                            padding: const EdgeInsets.all(20),
                                            child: PatientsScreen(
                                              ai: ai,
                                              repository: patients!,
                                              member: member,
                                              initialPatientId: id,
                                            ),
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
                else if (model.screen == 'Estadísticas')
                  DashboardScreen(
                    key: ValueKey((
                      auth?.active?.userId,
                      auth?.active?.clinicId,
                      auth?.offline,
                      moduleAccess,
                    )),
                    model: DashboardViewModel(
                      member: auth?.active,
                      backup: allowed('Estadísticas') ? backup : null,
                      moduleAccess: moduleAccess,
                    ),
                    offline: auth?.offline ?? false,
                    statisticsOnly: true,
                    onNavigate: model.navigate,
                  )
                else if (model.screen == 'Respaldo' ||
                    model.screen == 'Estadísticas y respaldo')
                  backup != null &&
                          allowed(model.screen) &&
                          auth?.offline != true
                      ? BackupScreen(
                          identity: identity,
                          repository: backup!,
                          member: auth!.active!,
                          backupOnly: model.screen == 'Respaldo',
                        )
                      : const Text(
                          'Las estadísticas y el respaldo requieren conexión y permiso vigente.',
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
    if (auth?.active != null)
      ClinicIdentity(
        key: ValueKey(
          "identity:${auth!.active!.userId}:${auth!.active!.clinicId}:${auth!.active!.role}",
        ),
        member: auth!.active!,
        repository: forms,
        identity: identity,
      ),
    _ModuleSearch(
      member: auth?.active,
      moduleAccess: moduleAccess,
      onNavigate: model.navigate,
    ),
    DashboardScreen(
      key: ValueKey((
        auth?.active?.userId,
        auth?.active?.clinicId,
        auth?.active?.role,
        auth?.offline,
        moduleAccess,
      )),
      model: DashboardViewModel(
        member: auth?.active,
        operations: operations,
        inventory: inventory,
        hospital: hospital,
        patients: patients,
        backup: backup,
        moduleAccess: moduleAccess,
      ),
      offline: auth?.offline ?? false,
      homePilot: true,
      alerts: hospitalAlerts,
      onNavigate: model.navigate,
    ),
    FirstStepsBanner(
      key: ValueKey('guide:${auth?.active?.userId}:${auth?.active?.clinicId}'),
      scope: '${auth?.active?.userId}:${auth?.active?.clinicId}',
      onOpen: () => model.navigate('Inicio guiado'),
    ),
  ];

  List<Widget> settings(BuildContext context) => [
    Text('Ajustes', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 24),
    Text('Estilo visual', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    Wrap(
      spacing: 12,
      children: [
        ChoiceChip(
          label: const Text('Clásico'),
          selected: model.settings.visualStyle == 'standard',
          onSelected: (_) => model.updateSettings(visualStyle: 'standard'),
        ),
        ChoiceChip(
          label: const Text('Neu · relieve suave'),
          selected: model.settings.visualStyle == 'neu',
          onSelected: (_) => model.updateSettings(visualStyle: 'neu'),
        ),
      ],
    ),
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
    if (operations is CommissionRepository &&
        auth?.active != null &&
        auth?.offline != true)
      ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: const Text('Mis comisiones'),
        subtitle: const Text('Saldo, próximo pago e historial'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Mis comisiones')),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: CommissionPanel(
                  repository: operations as CommissionRepository,
                  member: auth!.active!,
                ),
              ),
            ),
          ),
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
        'Respaldo',
      ),
      (
        'Ayuda y contacto',
        'Reportes, archivos y seguimiento.',
        'Ayuda y soporte',
      ),
      ('Primeros pasos', 'Retoma la guía de configuración.', 'Inicio guiado'),
    ])
      if (allowed(option.$3))
        ListTile(
          leading: Icon(sectionIcon(option.$3)),
          title: Text(option.$1),
          subtitle: Text(option.$2),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            if (option.$1 == 'Proveedor de IA y privacidad') {
              if (ai == null || auth?.active == null || auth?.offline == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'La configuración de IA requiere cuenta y conexión.',
                    ),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Proveedores de IA')),
                    body: SafeArea(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: AiScreen(
                          repository: ai!,
                          member: auth!.active!,
                          configurationOnly: true,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              model.navigate(option.$3);
            }
          },
        ),
    if (allowed('Hospitalización')) ...[
      const Divider(),
      Text(
        'Alertas y recordatorios',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      AlertPreferencesPanel(alerts: hospitalAlerts),
    ],
    const AppVersionLabel(),
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF131E2A) : VetColors.surface;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF182536), Color(0xFF101923)]
              : const [Color(0xFFFFFFFF), Color(0xFFF1F6FA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? const Color(0xFF243547) : const Color(0xFFE4EDF3),
        ),
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x99000000) : const Color(0xFFD5E0E7),
            offset: const Offset(7, 8),
            blurRadius: 18,
          ),
          BoxShadow(
            color: dark ? const Color(0x182DE6D1) : const Color(0xFFFFFFFF),
            offset: const Offset(-6, -6),
            blurRadius: 16,
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: dark ? 0.035 : 0.025),
            theme.colorScheme.secondary.withValues(alpha: dark ? 0.025 : 0.018),
            surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _ModuleSearch extends StatefulWidget {
  const _ModuleSearch({
    required this.member,
    required this.moduleAccess,
    required this.onNavigate,
  });
  final ClinicMembership? member;
  final ModuleAccess? moduleAccess;
  final ValueChanged<String> onNavigate;
  @override
  State<_ModuleSearch> createState() => _ModuleSearchState();
}

class _ModuleSearchState extends State<_ModuleSearch> {
  String query = '';
  static const pages = [
    'Más',
    'Cálculos',
    'Producción y grandes especies',
    'Servicios',
    'Proveedores',
    'Agenda telefónica',
    'Promociones',
    'Productividad y semana',
    'Agenda',
    'Pacientes',
    'Hospitalización',
    'Inventario',
    'Caja',
    'Planeación financiera',
    'Receta',
    'Formatos',
    'Cálculo rápido',
    'Operaciones de dosis',
    'Cálculos clínicos',
    'Estadísticas',
    'Escanear producto',
    'Equipo y avisos',
    'Pendientes del equipo',
    'Asistente IA',
    'Ayuda y soporte',
    'Ajustes',
    'Respaldo',
  ];
  String normalize(String value) => value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');
  @override
  Widget build(BuildContext context) {
    final results = pages
        .where(
          (p) =>
              navigationAllowed(p, widget.member, widget.moduleAccess) &&
              normalize(p).contains(normalize(query.trim())),
        )
        .toList();
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar apartados y herramientas',
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        if (query.trim().isNotEmpty) ...[
          if (results.isEmpty)
            const ListTile(title: Text('No hay apartados con ese nombre.')),
          for (final page in results)
            ListTile(
              leading: Icon(sectionIcon(page)),
              title: Text(page),
              onTap: () => widget.onNavigate(page),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
