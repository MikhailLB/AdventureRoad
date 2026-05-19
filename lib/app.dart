import 'package:flutter/material.dart';
import 'game/game_screen.dart';

class ChickenTripApp extends StatelessWidget {
  const ChickenTripApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Trip 2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.deepOrange,
          surface: Color(0xFF1A1A2E),
        ),
      ),
      home: const GameScreen(),
    );
  }
}
