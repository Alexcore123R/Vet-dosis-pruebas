import 'package:flutter/material.dart';
import '../../core/presentation/module_page.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/patient_view_model.dart' show newOperationId;
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';

const _days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
String _date(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

class ProductivityScreen extends StatefulWidget {
  const ProductivityScreen({super.key, required this.repository, required this.member, this.ai, this.embedded=false});
  final ProductivityRepository repository;
  final ClinicMembership member;
  final AiRepository? ai;
  final bool embedded;
  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen> {
  late DateTime week;
  Map<String,dynamic> data = {};
  bool busy = false;
  String? error;
  bool get manage => data['can_manage'] == true;
  List<Map<String,dynamic>> rows(String key) => (data[key] as List? ?? []).map((e) => Map<String,dynamic>.from(e as Map)).toList();
  Map<String,dynamic> get profile => Map<String,dynamic>.from(data['profile'] as Map? ?? {});
  Map<String,String> get people => {for (final m in rows('members')) '${m['id']}': '${m['name']}'};
  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    week = today.subtract(Duration(days: today.weekday-1));
    load();
  }
  Future<void> load() async {
    setState(() { busy=true;error=null;data={}; });
    try {
      final next = await widget.repository.productivity(widget.member.clinicId,_date(week));
      if (mounted) setState(() => data=next);
    } catch (_) {
      if (mounted) setState(() => error='No se pudo cargar la planificación. Revisa los permisos de equipo, el plan de la clínica y SQL 14L.');
    } finally { if (mounted) setState(() => busy=false); }
  }
  Future<void> write(String action,Map<String,dynamic> values,String operation) =>
    widget.repository.planWrite(widget.member.clinicId,action,values,operation);

  Future<void> entry(String title,String action,List<RxField> fields,Map<String,dynamic> initial) async {
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(builder: (_) => RxEntryScreen(
      title:title,fields:fields,initial:initial,submit:(values,op) async {
        try { await write(action,values,op); }
        catch (_) { throw const FormatException('No se pudo guardar. Actualiza para comprobar cambios, permisos y datos.'); }
      },
    )));
    if (saved==true && mounted) await load();
  }
  Future<void> editProfile() async {
    await entry('Recursos y objetivos de la clínica','profile',const [
      RxField('spaces','Espacios y capacidad (consultorios, jaulas, áreas)'),
      RxField('equipment','Equipo disponible y limitaciones'),
      RxField('services','Servicios que ofrece la clínica'),
      RxField('hours','Días y horarios de atención'),
      RxField('goals','Objetivos de productividad y dificultades'),
      RxField('budget','Presupuesto disponible o restricciones de inversión'),
      RxField('daily_minutes','Minutos por persona al día para tareas de apoyo',required:true),
    ], {...profile,'daily_minutes':'${profile['daily_minutes'] ?? 60}','availability':profile['availability'] ?? <String,dynamic>{}});
  }

  Future<void> availability() async {
    final available=Map<String,dynamic>.from(profile['availability'] as Map? ?? {});
    await Navigator.push<void>(context,MaterialPageRoute(builder: (_) => _AvailabilityEditor(
      people:people,initial:available,onSave:(value,op) => write('profile',{...profile,'availability':value},op),
    )));
    if (mounted) await load();
  }

  Future<void> routine([Map<String,dynamic>? row]) async {
    final saved=await Navigator.push<bool>(context,MaterialPageRoute(builder: (_) => _RoutineEditor(
      people:people,initial:row,onSave:(value,op) => write('routine',value,op),
    )));
    if (saved==true && mounted) await load();
  }
  Future<void> task([Map<String,dynamic>? row]) => entry('Tarea de la semana','task',[
    const RxField('title','Tarea',required:true),
    const RxField('scheduled_on','Fecha',type:'local_date',required:true),
    RxField('assigned_to','Responsable (vacío: sin asignar)',type:'select',options:people),
    const RxField('area','Área'),const RxField('instructions','Instrucciones'),
    const RxField('estimated_minutes','Duración estimada en minutos',required:true),
  ],row==null?{'scheduled_on':_date(week),'estimated_minutes':'15','priority':'media'}:{
    ...row,'estimated_minutes':'${row['estimated_minutes']}',
  });

  Future<void> generate() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Preparar tareas de la semana'),
      content:const Text('Se crearán las tareas de las rutinas activas y se repartirán por disponibilidad y minutos asignados. Las tareas sin una persona disponible quedarán sin asignar para que las revises. Las ya creadas se conservan.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Preparar semana'))],
    ));
    if (yes!=true || !mounted) return;
    await perform('generate',{'week':_date(week)});
  }
  Future<void> perform(String action,Map<String,dynamic> values) async {
    setState(()=>busy=true);
    try { await write(action,values,newOperationId());await load(); }
    catch (_) { if(mounted)setState(()=>error='No se pudo completar. Actualiza antes de reintentar.'); }
    finally { if(mounted)setState(()=>busy=false); }
  }

  Future<void> plan({bool useAi=false}) async {
    var body='${data['plan'] ?? ''}';
    if (useAi && widget.ai!=null) {
      final anonymousAvailability = people.keys.map((id) => (profile['availability'] as Map?)?[id] ?? [0,1,2,3,4,5,6]).toList();
      final result=await requestAiDraft(context,repository:widget.ai!,member:widget.member,title:'Plan de productividad',prompt:
        'Propón un plan semanal de productividad para una clínica veterinaria del ${_date(week)} al ${_date(week.add(const Duration(days:6)))}. '
        'Usa solo estos recursos declarados: espacios: ${profile['spaces'] ?? 'sin especificar'}; equipo: ${profile['equipment'] ?? 'sin especificar'}; '
        'servicios: ${profile['services'] ?? 'sin especificar'}; horarios: ${profile['hours'] ?? 'sin especificar'}; objetivos: ${profile['goals'] ?? 'sin especificar'}; '
        'restricciones de inversión: ${profile['budget'] ?? 'sin especificar'}. Equipo: ${people.length} personas, días disponibles anonimizados (0=lunes): $anonymousAvailability. '
        'Rutinas: ${rows('routines').map((r)=>{'tarea':r['title'],'dias':r['weekdays'],'minutos':r['estimated_minutes']}).toList()}. '
        'Incluye acciones priorizadas, responsables por función, duración, recursos, un indicador medible y revisión al cierre de semana. '
        'Distingue propuestas que requieren inversión. Pregunta por datos faltantes; no inventes resultados, ingresos ni demanda. '
        'Las tareas operativas deben respetar horarios y protocolos de la clínica. No incluyas tratamientos ni datos de pacientes. Devuelve un borrador de texto editable.');
      if (!mounted || result==null) return;
      body=result;
    }
    if(!mounted)return;
    await entry('Revisar plan semanal','plan',const [RxField('body','Plan y objetivos de la semana',required:true)],{'week':_date(week),'body':body});
  }
  @override
  Widget build(BuildContext context) {
    final tasks=rows('tasks');
    final completed=tasks.where((t)=>t['completed_at']!=null).length;
    final unassigned=tasks.where((t)=>t['assigned_to']==null&&t['completed_at']==null).length;
    return ModulePage(embedded:widget.embedded,title:'Productividad y semana',actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))],
      body:ListView(shrinkWrap:widget.embedded,physics:widget.embedded?const NeverScrollableScrollPhysics():null,padding:const EdgeInsets.all(16),children:[
        Row(children:[IconButton(onPressed:busy?null:(){week=week.subtract(const Duration(days:7));load();},icon:const Icon(Icons.chevron_left)),
          Expanded(child:Text('${_date(week)} — ${_date(week.add(const Duration(days:6)))}',textAlign:TextAlign.center)),
          IconButton(onPressed:busy?null:(){week=week.add(const Duration(days:7));load();},icon:const Icon(Icons.chevron_right))]),
        if(busy)const LinearProgressIndicator(),
        if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(!busy&&error==null)...[
          Text('$completed de ${tasks.length} tareas completadas · $unassigned sin asignar'),
          if(manage)...[
            if(data['can_profile']==true)Wrap(spacing:8,children:[
              OutlinedButton(onPressed:editProfile,child:const Text('Recursos y objetivos')),
              OutlinedButton(onPressed:availability,child:const Text('Disponibilidad del equipo')),
            ]),
            Wrap(spacing:8,children:[
              TextButton(onPressed:()=>plan(),child:const Text('Editar plan semanal')),
              if(widget.ai!=null)TextButton.icon(onPressed:()=>plan(useAi:true),icon:const Icon(Icons.auto_awesome),label:const Text('Sugerir plan con IA')),
            ]),
            if('${data['plan']??''}'.isNotEmpty)ExpansionTile(title:const Text('Plan de la semana'),children:[Padding(padding:const EdgeInsets.all(12),child:SelectableText('${data['plan']}'))]),
            ExpansionTile(title:const Text('Rutinas recurrentes'),children:[
              TextButton.icon(onPressed:()=>routine(),icon:const Icon(Icons.add),label:const Text('Agregar rutina')),
              for(final r in rows('routines'))ListTile(title:Text('${r['title']} · ${r['estimated_minutes']} min'),
                subtitle:Text((r['weekdays'] as List).map((d)=>_days[d as int]).join(', ')),
                onTap:()=>routine(r),trailing:IconButton(icon:const Icon(Icons.archive_outlined),onPressed:()async{
                  final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Archivar rutina'),content:Text('¿Archivar ${r['title']}? Se conservarán las tareas creadas.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Archivar'))]));
                  if(yes==true)await perform('archive',{'id':r['id'],'version':r['version']});
                })),
            ]),
            Wrap(spacing:8,children:[FilledButton(onPressed:generate,child:const Text('Preparar semana')),
              OutlinedButton(onPressed:()=>task(),child:const Text('Agregar tarea manual'))]),
          ],
          if(tasks.isEmpty)const Padding(padding:EdgeInsets.all(16),child:Text('Aún no hay tareas programadas para esta semana.')),
          for(var day=0;day<7;day++)if(tasks.any((t)=>t['scheduled_on']==_date(week.add(Duration(days:day)))))...[
            Padding(padding:const EdgeInsets.only(top:16),child:Text('${_days[day]} ${_date(week.add(Duration(days:day)))}',style:Theme.of(context).textTheme.titleMedium)),
            for(final t in tasks.where((t)=>t['scheduled_on']==_date(week.add(Duration(days:day)))))Card(child:ListTile(
              title:Text('${t['title']} · ${t['estimated_minutes']} min'),
              subtitle:Text('${people[t['assigned_to']]??'Sin asignar'} · ${t['area']}\n${t['instructions']}'),
              onTap:manage&&t['completed_at']==null?()=>task(t):null,
              trailing:t['completed_at']!=null?const Icon(Icons.task_alt):IconButton(icon:const Icon(Icons.check_box_outline_blank),tooltip:'Completar tarea',onPressed:()=>perform('complete',{'id':t['id']})),
            )),
          ],
        ],
      ]));
  }
}

class _RoutineEditor extends StatefulWidget {
  const _RoutineEditor({required this.people,required this.onSave,this.initial});
  final Map<String,String> people;
  final Map<String,dynamic>? initial;
  final Future<void> Function(Map<String,dynamic>,String) onSave;
  @override
  State<_RoutineEditor> createState()=>_RoutineEditorState();
}
class _RoutineEditorState extends State<_RoutineEditor> {
  late final title=TextEditingController(text:'${widget.initial?['title']??''}');
  late final area=TextEditingController(text:'${widget.initial?['area']??''}');
  late final notes=TextEditingController(text:'${widget.initial?['instructions']??''}');
  late final minutes=TextEditingController(text:'${widget.initial?['estimated_minutes']??15}');
  late final Set<int> days=(widget.initial?['weekdays'] as List? ?? [0]).cast<int>().toSet();
  late final Set<String> assignees=(widget.initial?['assignees'] as List? ?? []).cast<String>().toSet();
  bool busy=false;String? error;String operation=newOperationId(),previous='';
  @override
  void dispose(){title.dispose();area.dispose();notes.dispose();minutes.dispose();super.dispose();}
  Future<void> save() async {
    final count=int.tryParse(minutes.text);
    if(title.text.trim().isEmpty||days.isEmpty||count==null||count<1||count>480){setState(()=>error='Indica tarea, al menos un día y duración entre 1 y 480 minutos.');return;}
    final values=<String,dynamic>{if(widget.initial!=null)'id':widget.initial!['id'],if(widget.initial!=null)'version':widget.initial!['version'],
      'title':title.text.trim(),'area':area.text.trim(),'instructions':notes.text.trim(),'estimated_minutes':count,
      'weekdays':days.toList()..sort(),'assignees':assignees.where(widget.people.containsKey).toList()..sort()};
    final fingerprint=values.toString();if(previous.isNotEmpty&&previous!=fingerprint)operation=newOperationId();previous=fingerprint;
    setState((){busy=true;error=null;});
    try{await widget.onSave(values,operation);if(mounted)Navigator.pop(context,true);}
    catch(_){if(mounted)setState(()=>error='No se pudo guardar. Revisa datos, cambios del equipo y permisos.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Rutina semanal')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      if(widget.initial==null)Wrap(spacing:8,children:[for(final preset in ['Barrer','Trapear','Limpieza profunda'])ActionChip(label:Text(preset),onPressed:busy?null:()=>setState((){title.text=preset;minutes.text=preset=='Limpieza profunda'?'60':'15';}))]),
      TextField(controller:title,enabled:!busy,maxLength:150,decoration:const InputDecoration(labelText:'Tarea')),
      TextField(controller:area,enabled:!busy,maxLength:150,decoration:const InputDecoration(labelText:'Área')),
      TextField(controller:notes,enabled:!busy,maxLength:2000,maxLines:3,decoration:const InputDecoration(labelText:'Instrucciones y protocolo de la clínica')),
      TextField(controller:minutes,enabled:!busy,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Duración estimada en minutos')),
      const Text('Días de realización'),Wrap(spacing:4,children:[for(var i=0;i<7;i++)FilterChip(label:Text(_days[i]),selected:days.contains(i),onSelected:busy?null:(v)=>setState(()=>v?days.add(i):days.remove(i)))]),
      const Text('Personas que pueden realizarla (se alternan según disponibilidad y carga)'),
      for(final person in widget.people.entries)CheckboxListTile(title:Text(person.value),value:assignees.contains(person.key),onChanged:busy?null:(v)=>setState(()=>v==true?assignees.add(person.key):assignees.remove(person.key))),
      if(assignees.isEmpty)const Text('Sin personas seleccionadas: se crearán tareas sin asignar.'),
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      FilledButton(onPressed:busy?null:save,child:Text(busy?'Guardando…':'Guardar rutina')),
    ]));
}

class _AvailabilityEditor extends StatefulWidget {
  const _AvailabilityEditor({required this.people,required this.initial,required this.onSave});
  final Map<String,String> people;
  final Map<String,dynamic> initial;
  final Future<void> Function(Map<String,dynamic>,String) onSave;
  @override
  State<_AvailabilityEditor> createState()=>_AvailabilityEditorState();
}
class _AvailabilityEditorState extends State<_AvailabilityEditor>{
  late final Map<String,Set<int>> days={for(final id in widget.people.keys)id:(widget.initial[id] as List? ?? [0,1,2,3,4,5,6]).cast<int>().toSet()};
  bool busy=false;String? error;String operation=newOperationId();String previous='';
  Future<void> save() async {
    final values={for(final item in days.entries)item.key:item.value.toList()..sort()};
    final fingerprint=values.toString();if(previous.isNotEmpty&&previous!=fingerprint)operation=newOperationId();previous=fingerprint;
    setState((){busy=true;error=null;});
    try{await widget.onSave(values,operation);if(mounted)Navigator.pop(context);}
    catch(_){if(mounted)setState(()=>error='No se pudo guardar la disponibilidad.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Disponibilidad para tareas')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Selecciona los días en que cada persona puede realizar tareas de apoyo. Puedes dejar todos desmarcados si no participa en el reparto.'),
      for(final person in widget.people.entries)...[Text(person.value,style:Theme.of(context).textTheme.titleMedium),
        Wrap(spacing:4,children:[for(var i=0;i<7;i++)FilterChip(label:Text(_days[i]),selected:days[person.key]!.contains(i),onSelected:busy?null:(v)=>setState(()=>v?days[person.key]!.add(i):days[person.key]!.remove(i)))])],
      if(error!=null)Text(error!),FilledButton(onPressed:busy?null:save,child:const Text('Guardar disponibilidad')),
    ]));
}
