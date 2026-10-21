import 'package:flutter/material.dart';

/// Allows a module to share the host's scroll view or open as a full page.
class ModulePage extends StatelessWidget {
  const ModulePage({super.key,required this.title,required this.body,this.actions=const [],this.embedded=false});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool embedded;
  @override
  Widget build(BuildContext context)=>embedded?Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Text(title,style:Theme.of(context).textTheme.headlineSmall)),...actions]),body,
  ]):Scaffold(appBar:AppBar(title:Text(title),actions:actions),body:body);
}
