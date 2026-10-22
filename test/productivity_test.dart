import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vetdosis_pro/modules/auth/domain/clinic_membership.dart';
import 'package:vetdosis_pro/modules/operations/domain/operations_repository.dart';
import 'package:vetdosis_pro/modules/operations/presentation/productivity_screen.dart';
import 'package:vetdosis_pro/modules/ai/presentation/request_ai_draft.dart';
import 'ai_plans_test.dart' show AiFake, personal;

const member=ClinicMembership(clinicId:'clinic',clinicName:'Clínica',userId:'staff',role:ClinicRole.admin);
class ProductivityFake implements ProductivityRepository {
  bool manager=true;
  final writes=<String>[];
  @override
  Future<Map<String,dynamic>> productivity(String clinic,String week) async=>{
    'can_manage':manager,'can_profile':manager,'profile':{},'plan':'',
    'members':[{'id':'staff','name':'Ana'}],'routines':[],
    'tasks':[{'id':'task','title':'Barrer','estimated_minutes':15,'scheduled_on':week,'assigned_to':'staff','area':'Recepción','instructions':'','completed_at':null}],
  };
  @override
  Future<void> planWrite(String clinic,String action,Map<String,dynamic> data,String operation) async{writes.add(action);}
}
class DraftFake extends AiFake {
  @override
  Future<List<Map<String,dynamic>>> messages(String chat) async=>[{'role':'assistant','body':'Plan sugerido para revisar'}];
}
void main(){
  testWidgets('A weekly generation is explicit and cancellable',(tester)async{
    final repository=ProductivityFake();
    await tester.pumpWidget(MaterialApp(home:ProductivityScreen(repository:repository,member:member)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Preparar semana'));
    await tester.tap(find.text('Preparar semana'));
    await tester.pumpAndSettle();
    expect(repository.writes,isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repository.writes,isEmpty);
    await tester.tap(find.text('Preparar semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Preparar semana').last);
    await tester.pumpAndSettle();
    expect(repository.writes,['generate']);
  });
  testWidgets('Team reader sees assigned tasks without management controls',(tester)async{
    final repository=ProductivityFake()..manager=false;
    await tester.pumpWidget(MaterialApp(home:ProductivityScreen(repository:repository,member:member)));
    await tester.pumpAndSettle();
    expect(find.text('Barrer · 15 min'),findsOneWidget);
    expect(find.text('Recursos y objetivos'),findsNothing);
    expect(find.text('Preparar semana'),findsNothing);
    expect(tester.takeException(),isNull);
  });
  testWidgets('The planner also fits inside the host scroll view',(tester)async{
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ListView(children:[ProductivityScreen(embedded:true,repository:ProductivityFake(),member:member)]))));
    await tester.pumpAndSettle();
    expect(find.text('Productividad y semana'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('An AI response is returned only when explicitly selected',(tester)async{
    String? result;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{
      result=await requestAiDraft(context,repository:DraftFake(),member:personal,title:'Plan semanal',prompt:'Contexto sintético');
    },child:const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));await tester.pumpAndSettle();
    expect(result,isNull);
    await tester.ensureVisible(find.text('Usar como borrador editable'));
    await tester.tap(find.text('Usar como borrador editable'));await tester.pumpAndSettle();
    expect(result,'Plan sugerido para revisar');
    expect(tester.takeException(),isNull);
  });
}
