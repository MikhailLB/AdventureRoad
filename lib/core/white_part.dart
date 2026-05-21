// ════════════════════════════════════════════════════════════
// ⚠️  WHITE PART PLACEHOLDER — replace with your game
// ════════════════════════════════════════════════════════════
///
/// This file is the ONLY integration point between the gray flow
/// and your game (white part).
///
/// HOW TO INTEGRATE YOUR GAME:
///
///   1. Copy your game code into lib/core/ (or any subdirectory).
///   2. Replace [WhitePartPlaceholder] below with your root game
///      widget (e.g. GameScreen, PlayView, etc.).
///   3. Implement [MediaBundle.loadAll()] to preload your assets
///      (images, sounds, spritesheets) before the game starts.
///   4. The gray flow shows the game when:
///        a) First launch + backend returns no URL (organic user)
///        b) Returning user with AppState.offline stored
///
/// REQUIREMENTS for your game widget:
///   • Full-screen StatefulWidget
///   • Handles its own orientation locking if needed
///   • Should NOT depend on any gray-flow classes
///
/// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// ── TODO: Replace this widget with your actual game ──────────
class WhitePartPlaceholder extends StatelessWidget {
  const WhitePartPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_esports, size: 64, color: Colors.amber),
            SizedBox(height: 24),
            Text(
              'WHITE PART PLACEHOLDER',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Replace WhitePartPlaceholder in\nlib/core/white_part.dart\nwith your game widget.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── TODO: Implement asset preloading for your game ───────────
/// Called by LaunchPage before navigating to the game.
/// Add your asset loading logic here (images, audio, etc.).
class MediaBundle {
  Future<void> loadAll() async {
    // TODO: Preload your game assets here.
    // Example:
    //   await _loadImage('assets/player.png');
    //   await _loadImage('assets/Cars/taxi.webp');
    await Future.delayed(const Duration(milliseconds: 100)); // remove this
  }
}
