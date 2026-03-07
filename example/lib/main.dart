import 'package:example/resources/figma.g.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final extensions = width > 1024
        ? Figma.desktop
        : width > 600
        ? Figma.tablet
        : Figma.mobile;

    return MaterialApp(
      theme: ThemeData(extensions: extensions),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(context.spacing.spaceBlock),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text('_counter', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}
