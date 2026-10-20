import '../../prescribing/domain/prescribing_repository.dart';
import '../clinical/clinical_repository.dart';
import '../clinical/clinical_screen.dart';
import '../clinical/death_screen.dart';
import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/domain/patient_repository.dart';
import '../domain/form_models.dart';
import '../domain/form_repository.dart';
import 'form_view_model.dart';
import 'template_editor.dart';
import 'document_editor.dart';
import 'document_flow_screen.dart';
import 'form_pdf_screen.dart';
import 'branding_editor.dart';

class FormsScreen extends StatefulWidget {
  const FormsScreen({
    super.key,
    required this.repository,
    required this.patients,
    required this.member,
    this.clinical,
    this.prescribing,
  });
  final FormRepository repository;
  final ClinicalRepository? clinical;
  final PrescribingRepository? prescribing;
  final PatientRepository patients;
  final ClinicMembership member;
  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen> {
  late final FormViewModel model;
  bool professionalAdmin = false;
  @override
  void initState() {
    super.initState();
    model = FormViewModel(widget.repository, widget.member);
    model.load();
    if (widget.member.role == ClinicRole.admin && widget.prescribing != null) {
      loadProfessional();
    }
  }

  Future<void> loadProfessional() async {
    try {
      final rows = await widget.prescribing!.read('rx_profiles', {
        'p_clinic': widget.member.clinicId,
      });
      if (mounted) {
        setState(
          () => professionalAdmin = (rows as List).any(
            (p) =>
                p['user_id'] == widget.member.userId && p['authorized'] == true,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => professionalAdmin = false);
    }
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> editor(
    FormTemplateVersion version, {
    bool restore = false,
  }) async {
    Map<String, dynamic>? base;
    if (restore) {
      try {
        base = (await widget.repository.version(version.baseVersionId!)).schema;
      } catch (_) {
        message('No se pudo obtener la versión base exacta.');
        return;
      }
      if (!mounted) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TemplateEditor(
          repository: widget.repository,
          clinicId: widget.member.clinicId,
          original: version,
          restore: base,
          canApprove: model.canApproveTemplates,
        ),
      ),
    );
    if (mounted) await model.load();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> create(FormTemplateVersion version) async {
    try {
      final patients = await widget.patients.patients(widget.member.clinicId);
      final branding = await widget.repository.branding(widget.member.clinicId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DocumentEditor(
            repository: widget.repository,
            member: widget.member,
            professionalAdmin: professionalAdmin,
            prescribing: widget.prescribing,
            template: version,
            patients: patients,
            initialBranding: branding,
            draftOnly: model.documentsKnown,
            deferAuthorship: model.individualFlow,
            draftResponsibles: model.documentResponsibles,
          ),
        ),
      );
      if (mounted) await model.load();
    } catch (_) {
      message('No se pudieron consultar los pacientes.');
    }
  }

  bool canCreate(FormTemplateVersion version) => model.documentsKnown
      ? model.canCreateDraft(version)
      : (model.documentsAvailable &&
            (model.access.finalize || professionalAdmin) &&
            version.clinicId != null &&
            version.approved);

  Future<void> open(FormDocument doc) async {
    try {
      if (doc.signed) {
        final pdf = await widget.repository.pdf(doc.id);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                FormPdfScreen(pdf: pdf, title: 'PDF firmado', signed: true),
          ),
        );
      } else if (model.individualFlow) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DocumentFlowScreen(
              repository: widget.repository,
              id: doc.id,
              edit: (current, choices) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentEditor(
                      repository: widget.repository,
                      member: widget.member,
                      document: current,
                      fieldChoices: choices,
                      draftOnly: true,
                      draftResponsibles: model.documentResponsibles,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        if (model.documentsKnown && doc.snapshot['can_edit'] != true) {
          message(
            'Este borrador requiere revisión de su responsable antes de continuar.',
          );
          return;
        }
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DocumentEditor(
              repository: widget.repository,
              member: widget.member,
              professionalAdmin: professionalAdmin,
              prescribing: widget.prescribing,
              document: doc,
              draftOnly: model.documentsKnown,
              draftResponsibles: model.documentResponsibles,
            ),
          ),
        );
      }
      if (mounted) await model.load();
    } catch (_) {
      message('No se pudo abrir el documento. Revisa acceso y conexión.');
    }
  }

  Future<void> branding() async {
    if (model.templates.isEmpty) return;
    try {
      final data = await widget.repository.branding(widget.member.clinicId);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BrandingEditor(
            repository: widget.repository,
            clinicId: widget.member.clinicId,
            schema: model.templates.first.schema,
            initial: data,
          ),
        ),
      );
    } catch (_) {
      message('No se pudo abrir la configuración.');
    }
  }

  Future<void> history(FormTemplateVersion version) async {
    try {
      final items = await widget.repository.history(version.templateId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: ListView(
            children: [
              const ListTile(
                title: Text('Historial de versiones (solo lectura)'),
              ),
              for (final v in items)
                ListTile(
                  title: Text(
                    'Versión ${v.version} · ${v.approved ? 'aprobada por clínica' : 'pendiente de revisión'}',
                  ),
                  subtitle: Text(
                    '${v.reason}\n${v.createdAt ?? ''} · Autor: ${v.createdBy ?? 'catálogo base'}',
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (_) {
      message('No se pudo consultar el historial.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Formatos y consentimientos',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Plantillas de referencia. El contenido final es responsabilidad de la clínica. La aprobación de una plantilla no significa que un tutor haya firmado un documento.',
          ),
        ),
        if (!model.templateKnown && widget.member.role == ClinicRole.admin)
          const Text(
            'El administrador edita plantillas y consulta documentos. Para emitir clínicamente como administrador también necesita habilitación profesional vigente del servidor.',
          ),
        OutlinedButton.icon(
          onPressed: model.busy ? null : model.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
        if (model.canBrand)
          TextButton(
            onPressed: model.busy ? null : branding,
            child: const Text('Membrete y logo de la clínica'),
          ),
        if (model.busy) const LinearProgressIndicator(),
        if (model.error != null) Text(model.error!),
        if (widget.clinical != null && model.canOpenClinical)
          OutlinedButton(
            onPressed: model.busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ClinicalScreen(
                          repository: widget.clinical!,
                          prescribing: widget.prescribing,
                          forms: widget.repository,
                          member: widget.member,
                        ),
                      ),
                    );
                    if (mounted) await model.load();
                  },
            child: const Text('Casos clínicos, mediciones y actuaciones'),
          ),
        Text(
          '1. Configurar formatos de la clínica',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Aquí el equipo autorizado edita el texto fijo: cláusulas legales, explicaciones e indicaciones. También configura los campos que se llenarán al atender. Cada cambio crea una versión nueva; los documentos firmados conservan la versión que utilizaron.',
        ),
        if (!model.busy && model.error == null && model.templates.isEmpty)
          Text(
            model.templateKnown && !model.capability('can_read')
                ? 'Tu cuenta no tiene permiso para consultar plantillas. '
                      'Revisa Permisos y habilitación.'
                : 'No hay plantillas disponibles. Las plantillas deben '
                      'configurarse y revisarse antes de usarlas.',
          ),
        for (final version in model.templates)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.schema['title'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    version.clinicId == null
                        ? 'Base de referencia · sin verificar'
                        : 'Copia de clínica · versión ${version.version} · ${version.approved ? 'aprobada para uso por la clínica' : 'pendiente de revisión'}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (model.canEditTemplates &&
                          (model.templateKnown ||
                              version.clinicId == null ||
                              widget.member.role == ClinicRole.admin ||
                              version.responsibleId == widget.member.userId))
                        TextButton(
                          onPressed: model.busy ? null : () => editor(version),
                          child: Text(
                            version.clinicId == null
                                ? 'Crear copia / formato propio'
                                : 'Editar en nueva versión',
                          ),
                        ),
                      if (model.canEditTemplates &&
                          version.clinicId != null &&
                          version.baseVersionId != null &&
                          (model.templateKnown ||
                              widget.member.role == ClinicRole.admin ||
                              version.responsibleId == widget.member.userId))
                        TextButton(
                          onPressed: model.busy
                              ? null
                              : () => editor(version, restore: true),
                          child: const Text('Restaurar base en versión nueva'),
                        ),
                      TextButton(
                        onPressed: model.busy ? null : () => history(version),
                        child: const Text('Historial de versiones'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          '2. Llenar un consentimiento o formato',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Elige una plantilla aprobada. Los datos ya registrados del paciente aparecen vinculados. El tutor/propietario completa o confirma sus datos de identificación; el equipo captura los datos clínicos y del procedimiento. Las cláusulas e indicaciones se leen en el documento y no se editan durante el llenado.',
          ),
        ),
        if (!model.busy &&
            model.error == null &&
            !model.templates.any(canCreate))
          const Text('No hay formatos aprobados disponibles para llenar.'),
        for (final version in model.templates.where(canCreate))
          Card(
            child: ListTile(
              title: Text(version.schema['title']),
              subtitle: Text(
                'Versión ${version.version} · aprobada para uso por la clínica',
              ),
              trailing: const Icon(Icons.edit_note),
              onTap: model.busy ? null : () => create(version),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          '3. Documentos del expediente',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Llena un formato con los datos autorizados del paciente, revisa la vista previa, firma y guarda el PDF como evidencia inmutable.',
        ),
        if (model.documents.isEmpty && !model.busy)
          const Text('Sin documentos disponibles para tu acceso.'),
        for (final doc in model.documents) ...[
          ListTile(
            title: Text(doc.snapshot['schema']['title']),
            subtitle: Text(
              '${formStateLabel(doc.state)} · ${doc.snapshot['patient']['name']}\n'
              '${doc.signed ? 'Firmado y agregado al expediente' : 'Borrador editable'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: model.busy ? null : () => open(doc),
          ),
          if (widget.clinical != null &&
              doc.signed &&
              doc.snapshot['schema']['type'] == 'euthanasia')
            TextButton(
              onPressed: model.busy
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DeathScreen(
                            repository: widget.clinical!,
                            document: doc,
                            member: widget.member,
                          ),
                        ),
                      );
                    },
              child: const Text('Constatación posterior / correcciones'),
            ),
        ],
      ],
    ),
  );
}
