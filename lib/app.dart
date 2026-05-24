import 'package:flutter/material.dart';
import 'arena/arena_screen.dart';

class FeatherRunApp extends StatelessWidget {
  const FeatherRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feather Run',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0521),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFAA00FF),
          surface: Color(0xFF0D0521),
        ),
      ),
      home: const ArenaScreen(),
    );
  }
}
