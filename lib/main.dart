import 'modules/beta/domain/beta_repository.dart';
import 'modules/beta/data/supabase_beta_repository.dart';
import 'modules/identity/domain/identity_repository.dart';
import 'modules/identity/data/supabase_identity_repository.dart';
import 'modules/core/domain/build_channel.dart';
import 'modules/core/domain/module_access.dart';
import 'modules/core/data/supabase_module_access_repository.dart';
import 'modules/support/domain/support_repository.dart';
import 'modules/support/data/supabase_support_repository.dart';
import 'modules/ai/domain/ai_repository.dart';
import 'modules/ai/data/supabase_ai_repository.dart';
import 'modules/subscriptions/domain/subscription_repository.dart';
import 'modules/subscriptions/data/supabase_subscription_repository.dart';
import 'modules/operations/domain/operations_repository.dart';
import 'modules/operations/data/supabase_operations_repository.dart';
import 'modules/attendance/domain/attendance_repository.dart';
import 'modules/attendance/data/supabase_attendance_repository.dart';
import 'modules/backup/domain/backup_repository.dart';
import 'modules/backup/data/supabase_backup_repository.dart';
import 'modules/inventory/domain/inventory_repository.dart';
import 'modules/inventory/data/supabase_inventory_repository.dart';
import 'modules/prescribing/domain/prescribing_repository.dart';
import 'modules/prescribing/data/supabase_prescribing_repository.dart';
import 'modules/calculations/data/reference_library_repository.dart';
import 'modules/forms/clinical/clinical_repository.dart';
import 'modules/forms/domain/form_repository.dart';
import 'modules/forms/data/supabase_form_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'modules/hospital/application/hospital_alerts.dart';
import 'modules/hospital/application/native_alarm_backend.dart';
import 'modules/hospital/data/supabase_hospital_repository.dart';
import 'modules/hospital/domain/hospital_repository.dart';
import 'modules/hospital/domain/hospital_models.dart';
import 'modules/patients/domain/patient_repository.dart';
import 'modules/patients/data/supabase_patient_repository.dart';
import 'package:flutter/material.dart';
import 'core/app.dart';
import 'modules/doses/data/personal_dose_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'modules/auth/data/supabase_auth_repository.dart';
import 'modules/auth/presentation/auth_view_model.dart';
import 'modules/core/data/settings_repository.dart';
import 'modules/core/presentation/core_view_model.dart';
import 'modules/offline/data/local_database.dart';
import 'modules/offline/data/local_store.dart';
import 'modules/offline/application/sync_engine.dart';
import 'modules/offline/application/membership_sync_authority.dart';
import 'modules/offline/domain/offline_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = SettingsRepository();
  final settings = await repository.load();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const channel = String.fromEnvironment('APP_CHANNEL');
  validateBuildBackend(channel, url);
  const existingSchema = bool.fromEnvironment(
    'SUPABASE_EXISTING_SCHEMA',
    defaultValue: true,
  );
  const googleEnabled = bool.fromEnvironment('SUPABASE_GOOGLE_ENABLED');
  AuthViewModel? auth;
  BetaRepository? beta;
  SyncEngine? sync;
  PersonalDoseRepository? personalDoses;
  PatientRepository? patients;
  HospitalRepository? hospital;
  FormRepository? forms;
  IdentityRepository? identity;
  ClinicalRepository? clinical;
  PrescribingRepository? prescribing;
  ReferenceLibraryRepository? referenceLibrary;
  InventoryRepository? inventory;
  OperationsRepository? operations;
  AttendanceRepository? attendance;
  BackupRepository? backup;
  AiRepository? ai;
  SubscriptionRepository? subscriptions;
  SupportRepository? support;
  ModuleAccessRepository? moduleAccess;
  if (url.isNotEmpty && key.isNotEmpty) {
    const build = int.fromEnvironment('BETA_BUILD');
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      headers: channel == 'beta' ? {'x-vetdosis-build': '$build'} : null,
    );
    if (channel == 'beta') {
      beta = SupabaseBetaRepository(Supabase.instance.client, build);
    }
    personalDoses = SupabasePersonalDoseRepository(Supabase.instance.client);
    patients = SupabasePatientRepository(Supabase.instance.client);
    hospital = SupabaseHospitalRepository(Supabase.instance.client);
    forms = SupabaseFormRepository(Supabase.instance.client);
    identity = SupabaseIdentityRepository(Supabase.instance.client);
    clinical = SupabaseClinicalRepository(Supabase.instance.client);
    prescribing = SupabasePrescribingRepository(Supabase.instance.client);
    referenceLibrary = SupabaseReferenceLibraryRepository(Supabase.instance.client);
    inventory = SupabaseInventoryRepository(Supabase.instance.client);
    operations = SupabaseOperationsRepository(Supabase.instance.client);
    attendance = SupabaseAttendanceRepository(Supabase.instance.client);
    backup = SupabaseBackupRepository(Supabase.instance.client);
    ai = SupabaseAiRepository(Supabase.instance.client);
    support = SupabaseSupportRepository(Supabase.instance.client);
    subscriptions = SupabaseSubscriptionRepository(Supabase.instance.client);
    moduleAccess = SupabaseModuleAccessRepository(Supabase.instance.client);
    final localStore = LocalStore(await openOfflineDatabase());
    final authRepository = SupabaseAuthRepository(
      Supabase.instance.client,
      existingSchema: existingSchema,
    );
    // Domain adapters are registered when their versioned backend is implemented.
    sync = SyncEngine(
      localStore,
      MembershipSyncAuthority(authRepository, localStore),
      const [],
    );
    auth = AuthViewModel(
      authRepository,
      googleEnabled: googleEnabled,
      cache: localStore,
      syncStore: localStore,
      refreshInterval: const Duration(seconds: 30),
      onVerifiedAccess: (members) async {
        for (final member in members) {
          await sync!.synchronize(SyncScope(member.userId, member.clinicId));
        }
      },
    );
    await auth.start();
  }
  final core = CoreViewModel(repository, settings, syncEngine: sync);
  final backend = NativeAlarmBackend(
    onOpen: () => core.navigate('Hospitalización'),
  );
  final alerts = HospitalAlerts(backend, await SharedPreferences.getInstance());
  await alerts.initialize();
  Future<void> bindAlerts() async {
    final member = auth?.active;
    final scope = member != null && HospitalAccess(member.role).clinical
        ? '${member.userId}:${member.clinicId}:${member.role.name}'
        : null;
    try {
      await alerts.bind(scope);
    } catch (_) {
      alerts.reportFailure(
        'No se pudieron cancelar los avisos anteriores. Revisa los ajustes de notificaciones.',
      );
    }
  }

  await bindAlerts();
  auth?.addListener(bindAlerts);
  runApp(
    VetDosisApp(
      model: core,
      auth: auth,
      beta: beta,
      personalDoses: personalDoses,
      patients: patients,
      hospital: hospital,
      forms: forms,
      identity: identity,
      clinical: clinical,
      prescribing: prescribing,
      referenceLibrary: referenceLibrary,
      inventory: inventory,
      operations: operations,
      attendance: attendance,
      backup: backup,
      ai: ai,
      subscriptions: subscriptions,
      support: support,
      moduleAccess: moduleAccess,
      hospitalAlerts: alerts,
      requireAuth: true,
    ),
  );
}
