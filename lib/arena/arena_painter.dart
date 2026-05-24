import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'scene_assets.dart';
import 'arena_engine.dart';

class ArenaPainter extends CustomPainter {
  final ArenaEngine engine;
  final SceneAssets assets;
  final HeroVariant activeHero;

  ArenaPainter({required this.engine, required this.assets, this.activeHero = HeroVariant.classic});

  // ── Neon sci-fi palette ──
  static const Color voidBg      = Color(0xFF0D0521);
  static const Color voidBgMid   = Color(0xFF110830);
  static const Color zoneA       = Color(0xFF1A1040);
  static const Color zoneB       = Color(0xFF130D30);
  static const Color neonPurple  = Color(0xFF7B2FBE);
  static const Color neonCyan    = Color(0xFF2AFFD8);
  static const Color neonCyanDim = Color(0xFF0ABFA0);
  static const Color gridLine    = Color(0xFF1E2A50);
  static const Color laneBase    = Color(0xFF0F0F1A);
  static const Color laneAlt     = Color(0xFF121220);
  static const Color markingCyan = Color(0x882AFFD8);
  static const Color markingSolid= Color(0xCC2AFFD8);
  static const Color turboBase   = Color(0xFF1A0830);
  static const Color turboGlow   = Color(0xFFAA00FF);

  static const double _curbH = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(engine.shakeX, engine.shakeY);

    _drawBackground(canvas, size);
    _drawLanes(canvas, size);
    _drawChips(canvas, size);
    _drawHazardShadows(canvas, size);
    _drawHazards(canvas, size);

    if (engine.state == ArenaState.playing ||
        engine.state == ArenaState.paused ||
        engine.state == ArenaState.gameOver) {
      _drawHeroShadow(canvas);
      _drawHero(canvas);
      if (engine.comboActive && engine.state == ArenaState.playing) {
        _drawComboIndicator(canvas);
      }
    }

    canvas.restore();

    if (engine.state == ArenaState.gameOver) {
      _drawDeathOverlay(canvas, size);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [voidBgMid, voidBg],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    // subtle star-field dots
    final rng = Random(42);
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.15);
    for (int s = 0; s < 60; s++) {
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        0.5 + rng.nextDouble() * 1.0,
        starPaint,
      );
    }
  }

  void _drawLanes(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 6).floor();
    final maxLane =
        (engine.cameraLane + size.height / ArenaEngine.laneHeight + 6).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final row = engine.lanes[i];
      if (row == null) continue;

      final centerY = engine.laneScreenY(i.toDouble());
      final top = centerY - ArenaEngine.laneHeight / 2;
      final rect = Rect.fromLTWH(0, top, size.width, ArenaEngine.laneHeight);

      if (row.isSafe) {
        _drawSafeZone(canvas, rect, row, size);
      } else {
        _drawCombatLane(canvas, rect, row, size);
      }
    }
  }

  // ── SAFE ZONE ──

  void _drawSafeZone(Canvas canvas, Rect rect, GridRow row, Size size) {
    final rng = Random(row.index * 7);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(zoneA, zoneB, 0.3)!,
            zoneA,
            Color.lerp(zoneA, voidBg, 0.4)!,
          ],
        ).createShader(rect),
    );

    // neon hex grid overlay
    final hexPaint = Paint()
      ..color = neonPurple.withValues(alpha: 0.07)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    const hexW = 22.0;
    for (double hx = 0; hx < size.width + hexW; hx += hexW * 1.5) {
      for (int row2 = 0; row2 < 2; row2++) {
        final hy = rect.top + rect.height * 0.5 + (row2 == 0 ? -6.0 : 6.0);
        final hexPath = Path();
        for (int p = 0; p < 6; p++) {
          final a = pi / 3 * p - pi / 6;
          final px = hx + hexW * 0.5 * cos(a);
          final py = hy + hexW * 0.5 * sin(a);
          p == 0 ? hexPath.moveTo(px, py) : hexPath.lineTo(px, py);
        }
        hexPath.close();
        canvas.drawPath(hexPath, hexPaint);
      }
    }

    // energy particles
    for (int p = 0; p < 8; p++) {
      final px = rng.nextDouble() * size.width;
      final py = rect.top + rng.nextDouble() * rect.height;
      final pr = 1.0 + rng.nextDouble() * 2.0;
      canvas.drawCircle(
        Offset(px, py),
        pr,
        Paint()..color = neonCyan.withValues(alpha: 0.15 + rng.nextDouble() * 0.1),
      );
    }

    // neon curbs
    _drawNeonCurb(canvas, Rect.fromLTWH(0, rect.top, size.width, _curbH), false);
    _drawNeonCurb(canvas, Rect.fromLTWH(0, rect.bottom - _curbH, size.width, _curbH), true);

    // decorations
    for (final deco in row.decorations) {
      final info = _propInfo(deco.type);
      final s = info.baseSize * deco.scale;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(deco.x + 3, rect.center.dy + s * 0.33),
          width: s * 0.6,
          height: s * 0.2,
        ),
        Paint()..color = neonPurple.withValues(alpha: 0.25),
      );
      if (deco.flipX) {
        canvas.save();
        canvas.translate(deco.x, rect.center.dy - s * 0.1);
        canvas.scale(-1, 1);
        _drawImage(canvas, info.img, -s / 2, -s * 0.5, s, s);
        canvas.restore();
      } else {
        _drawImage(canvas, info.img, deco.x - s / 2, rect.center.dy - s * 0.6, s, s);
      }
    }
  }

  void _drawNeonCurb(Canvas canvas, Rect rect, bool flipped) {
    canvas.drawRect(rect, Paint()..color = neonPurple.withValues(alpha: 0.35));
    canvas.drawRect(
      Rect.fromLTWH(rect.left, flipped ? rect.bottom - 1.5 : rect.top, rect.width, 1.5),
      Paint()..color = neonCyan.withValues(alpha: 0.7),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, flipped ? rect.top : rect.bottom - 1.5, rect.width, 1.5),
      Paint()..color = neonPurple.withValues(alpha: 0.4),
    );
    // segmented glow blocks
    const blockW = 18.0;
    double x = 0;
    while (x < rect.width) {
      canvas.drawRect(
        Rect.fromLTWH(x + 1, rect.top + 1, blockW - 2, rect.height - 2),
        Paint()..color = neonCyan.withValues(alpha: 0.06),
      );
      x += blockW;
    }
  }

  _PropDrawInfo _propInfo(PropType type) {
    switch (type) {
      case PropType.tower:  return _PropDrawInfo(assets.envTower, 64);
      case PropType.nodeA:  return _PropDrawInfo(assets.envNodeA, 52);
      case PropType.nodeB:  return _PropDrawInfo(assets.envNodeB, 50);
      case PropType.barrier:return _PropDrawInfo(assets.envGate, 48);
      case PropType.lamp:   return _PropDrawInfo(assets.envLight, 56);
    }
  }

  // ── COMBAT LANE ──

  void _drawCombatLane(Canvas canvas, Rect rect, GridRow row, Size size) {
    final rng = Random(row.index * 13);
    final baseCol = row.isTurbo ? turboBase : (row.index.isEven ? laneBase : laneAlt);
    canvas.drawRect(rect, Paint()..color = baseCol);

    // turbo glow overlay
    if (row.isTurbo) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              turboGlow.withValues(alpha: 0.18),
              turboGlow.withValues(alpha: 0.08),
              turboGlow.withValues(alpha: 0.18),
            ],
          ).createShader(rect),
      );
      // turbo side glow lines
      final glowPaint = Paint()
        ..color = turboGlow.withValues(alpha: 0.5)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, rect.top + 2), Offset(size.width, rect.top + 2), glowPaint);
      canvas.drawLine(Offset(0, rect.bottom - 2), Offset(size.width, rect.bottom - 2), glowPaint);
    }

    // subtle asphalt noise
    final texPaint = Paint();
    for (int n = 0; n < 16; n++) {
      final nx = rng.nextDouble() * size.width;
      final ny = rect.top + rng.nextDouble() * rect.height;
      texPaint.color = (rng.nextBool() ? neonCyan : neonPurple)
          .withValues(alpha: 0.025 + rng.nextDouble() * 0.02);
      canvas.drawCircle(Offset(nx, ny), 0.5 + rng.nextDouble() * 1.5, texPaint);
    }

    // segment border
    final borderColor = row.isTurbo ? turboGlow : neonCyan;
    if (row.isSegmentStart) {
      canvas.drawRect(
        Rect.fromLTWH(0, rect.top, size.width, 3),
        Paint()..color = borderColor.withValues(alpha: 0.8),
      );
    }
    if (row.isSegmentEnd) {
      canvas.drawRect(
        Rect.fromLTWH(0, rect.bottom - 3, size.width, 3),
        Paint()..color = borderColor.withValues(alpha: 0.8),
      );
    }

    // dashed cyan lane dividers
    if (!row.isSegmentStart) {
      final dashPaint = Paint()
        ..color = markingCyan
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      double x = 8;
      while (x < size.width) {
        canvas.drawLine(Offset(x, rect.top + 0.5), Offset(x + 18, rect.top + 0.5), dashPaint);
        x += 34;
      }
    }

    // column grid
    final gridPaint = Paint()
      ..color = gridLine.withValues(alpha: 0.4)
      ..strokeWidth = 0.6;
    for (int col = 1; col < ArenaEngine.numColumns; col++) {
      final cx = col * engine.columnWidth;
      canvas.drawLine(Offset(cx, rect.top), Offset(cx, rect.bottom), gridPaint);
    }

    // surface decorations
    for (final sd in row.surfaceDecos) {
      switch (sd.type) {
        case SurfaceDecoType.panel:
          _drawImage(canvas, assets.tokenB, sd.x - 16, rect.center.dy - 16, 32, 32);
        case SurfaceDecoType.panel2:
          _drawImage(canvas, assets.tokenB, sd.x - 16, rect.center.dy - 16, 32, 32);
        case SurfaceDecoType.skidMark:
          final skidPaint = Paint()
            ..color = neonCyan.withValues(alpha: 0.12)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(sd.x - 25, rect.center.dy - 4), Offset(sd.x + 25, rect.center.dy + 4), skidPaint);
          canvas.drawLine(Offset(sd.x - 22, rect.center.dy + 2), Offset(sd.x + 22, rect.center.dy + 8), skidPaint);
        case SurfaceDecoType.crack:
          final crackPaint = Paint()
            ..color = neonPurple.withValues(alpha: 0.3)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;
          final path = Path()
            ..moveTo(sd.x - 12, rect.center.dy - 10)
            ..lineTo(sd.x - 2, rect.center.dy - 2)
            ..lineTo(sd.x + 3, rect.center.dy - 5)
            ..lineTo(sd.x + 8, rect.center.dy + 2)
            ..lineTo(sd.x + 14, rect.center.dy + 8);
          canvas.drawPath(path, crackPaint);
      }
    }

    // direction arrows (neon cyan tint)
    final arrowColor = row.isTurbo ? turboGlow.withValues(alpha: 0.12) : neonCyan.withValues(alpha: 0.08);
    final arrowPaint = Paint()..color = arrowColor..style = PaintingStyle.fill;
    if (row.movingRight) {
      for (double ax = 50; ax < size.width; ax += 120) {
        final path = Path()
          ..moveTo(ax, rect.center.dy - 8)
          ..lineTo(ax + 14, rect.center.dy)
          ..lineTo(ax, rect.center.dy + 8)
          ..close();
        canvas.drawPath(path, arrowPaint);
      }
    } else {
      for (double ax = size.width - 50; ax > 0; ax -= 120) {
        final path = Path()
          ..moveTo(ax, rect.center.dy - 8)
          ..lineTo(ax - 14, rect.center.dy)
          ..lineTo(ax, rect.center.dy + 8)
          ..close();
        canvas.drawPath(path, arrowPaint);
      }
    }
  }

  // ── CHIPS ──

  void _drawChips(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane = (engine.cameraLane + size.height / ArenaEngine.laneHeight + 4).ceil();
    final colW = engine.columnWidth;
    final time = engine.menuTime;

    for (int i = minLane; i <= maxLane; i++) {
      final row = engine.lanes[i];
      if (row == null) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final chip in row.chips) {
        if (chip.collected) continue;
        final cx = chip.column * colW + colW / 2;
        final bobOffset = sin(time * 4.5 + chip.column * 1.7 + i * 0.3) * 3.5;

        // chip shadow/glow
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, laneY + 12), width: 20, height: 7),
          Paint()..color = (row.isTurbo ? turboGlow : neonCyan).withValues(alpha: 0.25),
        );

        // coin image
        _drawImage(canvas, assets.tokenA, cx - 14, laneY - 16 + bobOffset, 28, 28);

        // animated glow
        final shimmer = ((sin(time * 6 + chip.column * 2.5) + 1) / 2 * 0.35).clamp(0.0, 0.35);
        final glowColor = row.isTurbo
            ? turboGlow.withValues(alpha: shimmer)
            : const Color(0xFFFF6FFF).withValues(alpha: shimmer);
        canvas.drawCircle(
          Offset(cx, laneY - 2 + bobOffset),
          14,
          Paint()
            ..color = glowColor
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
    }
  }

  // ── HAZARDS ──

  void _drawHazardShadows(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane = (engine.cameraLane + size.height / ArenaEngine.laneHeight + 4).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final row = engine.lanes[i];
      if (row == null || row.isSafe) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final hazard in row.vehicles) {
        final img = assets.imageForHazard(hazard.type);
        final carH = ArenaEngine.laneHeight * 0.85;
        final aspect = img.width / img.height;
        final carW = carH * aspect;
        final glowColor = row.isTurbo ? turboGlow : neonCyan;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(hazard.x + 5, laneY + carH * 0.2), width: carW * 0.78, height: carH * 0.3),
          Paint()
            ..color = glowColor.withValues(alpha: row.isTurbo ? 0.4 : 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }
  }

  void _drawHazards(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane = (engine.cameraLane + size.height / ArenaEngine.laneHeight + 4).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final row = engine.lanes[i];
      if (row == null || row.isSafe) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final hazard in row.vehicles) {
        final img = assets.imageForHazard(hazard.type);
        final carH = ArenaEngine.laneHeight * 0.85;
        final aspect = img.width / img.height;
        final carW = carH * aspect;

        canvas.save();
        canvas.translate(hazard.x, laneY);
        canvas.rotate(hazard.movingRight ? -pi / 2 : pi / 2);
        _drawImage(canvas, img, -carW / 2, -carH / 2, carW, carH);
        canvas.restore();
      }
    }
  }

  // ── HERO ──

  void _drawHeroShadow(Canvas canvas) {
    final laneY = engine.laneScreenY(engine.heroLane.toDouble());
    final shadowW = engine.columnWidth * 0.6;
    final shadowX = engine.heroScreenX + 2;
    final shadowY = laneY + engine.columnWidth * 0.1;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(shadowX, shadowY), width: shadowW, height: shadowW * 0.35),
      Paint()
        ..color = neonCyan.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _drawHero(Canvas canvas) {
    final isDead = engine.state == ArenaState.gameOver;
    final heroScale = activeHero == HeroVariant.classic ? 1.0 : 2.0;
    final heroSize = engine.columnWidth * 0.85 * heroScale;
    final half = heroSize / 2;

    canvas.save();
    canvas.translate(engine.heroScreenX, engine.heroScreenY);

    if (engine.facingDir == -1) canvas.scale(-1, 1);

    if (isDead) {
      final img = assets.heroDead(activeHero);
      final t = engine.deathTimer.clamp(0.0, 1.0);
      canvas.rotate(t * 0.12);
      canvas.scale(1.0 + t * 0.2, 1.0 - t * 0.35);
      _drawImage(canvas, img, -half, -half, heroSize, heroSize);
    } else {
      final img = assets.heroAlive(activeHero);
      if (engine.hopProgress >= 1.0 && engine.idleTime > 0.3) {
        final breathe = 1.0 + sin((engine.idleTime - 0.3) * 2.5) * 0.03;
        canvas.scale(breathe, breathe);
      } else if (engine.hopProgress < 1.0) {
        final squash = 1.0 - sin(engine.hopProgress * pi) * 0.12;
        final stretch = 1.0 + sin(engine.hopProgress * pi) * 0.12;
        canvas.scale(squash, stretch);
      }
      _drawImage(canvas, img, -half, -half, heroSize, heroSize);
    }

    canvas.restore();
  }

  // ── COMBO INDICATOR ──

  void _drawComboIndicator(Canvas canvas) {
    final t = engine.menuTime;
    final pulse = (sin(t * 8) + 1) / 2;
    final alpha = 0.6 + pulse * 0.4;
    final glowRadius = 12 + pulse * 5;
    final x = engine.heroScreenX;
    final y = engine.heroScreenY - engine.columnWidth * 0.7;

    canvas.drawCircle(
      Offset(x, y),
      glowRadius,
      Paint()
        ..color = const Color(0xFFFF6FFF).withValues(alpha: 0.25 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      Offset(x, y),
      6,
      Paint()..color = const Color(0xFFFF6FFF).withValues(alpha: alpha),
    );
  }

  // ── DEATH FX ──

  void _drawDeathOverlay(Canvas canvas, Size size) {
    final flashAlpha = (1.0 - engine.deathTimer * 3).clamp(0.0, 0.45);
    if (flashAlpha > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = turboGlow.withValues(alpha: flashAlpha),
      );
    }

    if (engine.deathTimer > 0.15) {
      final sparkAlpha = ((engine.deathTimer - 0.15) * 2).clamp(0.0, 0.9);
      const sparkSize = 250.0;
      final cx = engine.heroScreenX + engine.shakeX;
      final cy = engine.heroScreenY + engine.shakeY;
      final paint = Paint()
        ..colorFilter = ColorFilter.mode(
          neonCyan.withValues(alpha: sparkAlpha),
          BlendMode.modulate,
        );
      final src = Rect.fromLTWH(0, 0, assets.burst.width.toDouble(), assets.burst.height.toDouble());

      for (int f = 0; f < 3; f++) {
        final angle = engine.deathTimer * (1.5 + f * 0.7);
        final dist = engine.deathTimer * 40 * (f + 1);
        final fx = cx + cos(angle) * dist;
        final fy = cy + sin(angle) * dist - engine.deathTimer * 20;
        final dst = Rect.fromCenter(center: Offset(fx, fy), width: sparkSize * 0.6, height: sparkSize * 0.6);
        canvas.save();
        canvas.translate(fx, fy);
        canvas.rotate(angle * 0.5);
        canvas.translate(-fx, -fy);
        canvas.drawImageRect(assets.burst, src, dst, paint);
        canvas.restore();
      }
    }
  }

  // ── UTIL ──

  void _drawImage(Canvas canvas, ui.Image img, double x, double y, double w, double h) {
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromLTWH(x, y, w, h);
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _PropDrawInfo {
  final ui.Image img;
  final double baseSize;
  _PropDrawInfo(this.img, this.baseSize);
}
