import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'media_bundle.dart';
import 'road_controller.dart';

class SceneRenderer extends CustomPainter {
  final RoadController engine;
  final MediaBundle assets;
  final CharSkinType activeSkin;

  SceneRenderer({required this.engine, required this.assets, this.activeSkin = CharSkinType.classic});

  static const Color roadColor = Color(0xFF505050);
  static const Color roadAlt = Color(0xFF484848);
  static const Color grassA = Color(0xFF6ECC6E);
  static const Color grassB = Color(0xFF5CB85C);
  static const Color grassC = Color(0xFF4CAF50);
  static const Color grassD = Color(0xFF3E9E41);
  static const Color grassE = Color(0xFF358635);
  static const Color curbTop = Color(0xFFAAAAAA);
  static const Color curbFace = Color(0xFF8A8A8A);
  static const Color curbLine = Color(0xFF707070);
  static const Color curbDark = Color(0xFF555555);
  static const Color lineWhite = Color(0xCCFFFFFF);
  static const Color lineSolid = Color(0xDDFFFFFF);

  static const double _curbH = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(engine.shakeX, engine.shakeY);

    _drawBackground(canvas, size);
    _drawLanes(canvas, size);
    _drawCoins(canvas, size);
    _drawVehicleShadows(canvas, size);
    _drawVehicles(canvas, size);

    if (engine.state == AppPhase.playing ||
        engine.state == AppPhase.paused ||
        engine.state == AppPhase.gameOver) {
      _drawCharacterShadow(canvas);
      _drawCharacter(canvas);
    }

    canvas.restore();

    if (engine.state == AppPhase.gameOver) {
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
          colors: [grassE, grassC],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  void _drawLanes(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 6).floor();
    final maxLane =
        (engine.cameraLane + size.height / RoadController.laneHeight + 6).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final lane = engine.lanes[i];
      if (lane == null) continue;

      final centerY = engine.laneScreenY(i.toDouble());
      final top = centerY - RoadController.laneHeight / 2;
      final rect = Rect.fromLTWH(0, top, size.width, RoadController.laneHeight);

      if (lane.isSafe) {
        _drawSafeLane(canvas, rect, lane, size);
      } else {
        _drawRoadLane(canvas, rect, lane, size);
      }
    }
  }

  void _drawSafeLane(Canvas canvas, Rect rect, TrackRow lane, Size size) {
    final rng = Random(lane.index * 7);

    final shift = (rng.nextInt(3) - 1) * 8;
    final baseColor = Color.fromARGB(
        255,
        (grassC.r * 255 + shift).round().clamp(0, 255),
        (grassC.g * 255 + shift).round().clamp(0, 255),
        (grassC.b * 255 + shift).round().clamp(0, 255));
    final lighter = Color.lerp(baseColor, grassA, 0.25)!;
    final darker = Color.lerp(baseColor, grassE, 0.25)!;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lighter, baseColor, darker],
        ).createShader(rect),
    );

    for (int p = 0; p < 5; p++) {
      final px = rng.nextDouble() * size.width;
      final py = rect.top + rng.nextDouble() * rect.height;
      final pr = 12 + rng.nextDouble() * 18;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(px, py), width: pr * 2, height: pr),
        Paint()
          ..color = (rng.nextBool() ? grassA : grassE).withValues(alpha: 0.15),
      );
    }

    final speckPaint = Paint();
    for (int g = 0; g < 18; g++) {
      final gx = rng.nextDouble() * size.width;
      final gy = rect.top + 4 + rng.nextDouble() * (rect.height - 8);
      speckPaint.color = (rng.nextBool() ? grassD : grassA)
          .withValues(alpha: 0.2 + rng.nextDouble() * 0.15);
      canvas.drawCircle(Offset(gx, gy), 0.8 + rng.nextDouble() * 1.5, speckPaint);
    }

    final tuftPaint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int t = 0; t < 12; t++) {
      final tx = rng.nextDouble() * size.width;
      final ty = rect.top + 6 + rng.nextDouble() * (rect.height - 12);
      final h = 3.5 + rng.nextDouble() * 3.5;
      tuftPaint.color = (rng.nextBool() ? grassD : grassE)
          .withValues(alpha: 0.35 + rng.nextDouble() * 0.2);
      canvas.drawLine(Offset(tx - 1.5, ty), Offset(tx, ty - h), tuftPaint);
      canvas.drawLine(Offset(tx + 1.5, ty), Offset(tx, ty - h), tuftPaint);
    }

    for (int f = 0; f < 3 + rng.nextInt(3); f++) {
      final fx = rng.nextDouble() * size.width;
      final fy = rect.top + 8 + rng.nextDouble() * (rect.height - 16);
      final fSize = 2.0 + rng.nextDouble() * 2.0;
      final flowerColors = [
        const Color(0xFFFF7043),
        const Color(0xFFFFCA28),
        const Color(0xFFAB47BC),
        const Color(0xFFEF5350),
        const Color(0xFFFF8A65),
      ];
      final fc = flowerColors[rng.nextInt(flowerColors.length)];
      canvas.drawCircle(Offset(fx, fy), fSize, Paint()..color = fc.withValues(alpha: 0.7));
      canvas.drawCircle(Offset(fx, fy), fSize * 0.4,
          Paint()..color = Colors.yellow.withValues(alpha: 0.8));
    }

    final leafPaint = Paint()..style = PaintingStyle.fill;
    for (int l = 0; l < 2 + rng.nextInt(3); l++) {
      final lx = rng.nextDouble() * size.width;
      final ly = rect.top + 6 + rng.nextDouble() * (rect.height - 12);
      final angle = rng.nextDouble() * pi * 2;
      final leafColors = [
        const Color(0xFFD84315),
        const Color(0xFFBF360C),
        const Color(0xFFF9A825),
        const Color(0xFF8D6E63),
      ];
      leafPaint.color =
          leafColors[rng.nextInt(leafColors.length)].withValues(alpha: 0.5);
      canvas.save();
      canvas.translate(lx, ly);
      canvas.rotate(angle);
      final leafPath = Path()
        ..moveTo(0, -3)
        ..quadraticBezierTo(4, -1, 0, 3)
        ..quadraticBezierTo(-4, -1, 0, -3);
      canvas.drawPath(leafPath, leafPaint);
      canvas.restore();
    }

    _drawStoneCurb(canvas, Rect.fromLTWH(0, rect.top, size.width, _curbH), rng, false);
    _drawStoneCurb(canvas, Rect.fromLTWH(0, rect.bottom - _curbH, size.width, _curbH), rng, true);

    for (final deco in lane.decorations) {
      final info = _itemMeta(deco.type);
      final s = info.baseSize * deco.scale;

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(deco.x + 3, rect.center.dy + s * 0.33),
          width: s * 0.6,
          height: s * 0.2,
        ),
        Paint()..color = const Color(0x44000000),
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

  void _drawStoneCurb(Canvas canvas, Rect rect, Random rng, bool flipped) {
    canvas.drawRect(rect, Paint()..color = curbFace);

    canvas.drawRect(
      Rect.fromLTWH(rect.left, flipped ? rect.bottom - 1 : rect.top, rect.width, 1.5),
      Paint()..color = curbTop,
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, flipped ? rect.top : rect.bottom - 1.5, rect.width, 1.5),
      Paint()..color = curbDark,
    );

    final groovePaint = Paint()
      ..color = curbLine
      ..strokeWidth = 0.8;
    const brickW = 18.0;
    final offset = (rng.nextDouble() * brickW).roundToDouble();
    double x = -brickW + offset;
    int row = 0;
    while (x < rect.width + brickW) {
      final bx = x + (row.isEven ? 0 : brickW / 2);
      canvas.drawLine(
        Offset(bx, rect.top + 1),
        Offset(bx, rect.bottom - 1),
        groovePaint,
      );
      x += brickW;
      row++;
    }
    if (rect.height > 5) {
      canvas.drawLine(
        Offset(rect.left, rect.center.dy),
        Offset(rect.right, rect.center.dy),
        groovePaint,
      );
    }
  }

  _ItemMeta _itemMeta(SceneryKind type) {
    switch (type) {
      case SceneryKind.tree:
        return _ItemMeta(assets.tree, 64);
      case SceneryKind.bush1:
        return _ItemMeta(assets.bush1, 52);
      case SceneryKind.bush2:
        return _ItemMeta(assets.bush2, 50);
      case SceneryKind.barrier:
        return _ItemMeta(assets.barrier, 48);
      case SceneryKind.fanar:
        return _ItemMeta(assets.fanar, 56);
    }
  }

  void _drawRoadLane(Canvas canvas, Rect rect, TrackRow lane, Size size) {
    final rng = Random(lane.index * 13);
    final baseCol = lane.index.isEven ? roadColor : roadAlt;
    canvas.drawRect(rect, Paint()..color = baseCol);

    final texPaint = Paint();
    for (int n = 0; n < 20; n++) {
      final nx = rng.nextDouble() * size.width;
      final ny = rect.top + rng.nextDouble() * rect.height;
      texPaint.color = (rng.nextBool() ? Colors.white : Colors.black)
          .withValues(alpha: 0.03 + rng.nextDouble() * 0.02);
      canvas.drawCircle(Offset(nx, ny), 0.5 + rng.nextDouble() * 1.5, texPaint);
    }

    if (lane.isSegmentStart) {
      canvas.drawRect(
        Rect.fromLTWH(0, rect.top, size.width, 3),
        Paint()..color = lineSolid,
      );
    }
    if (lane.isSegmentEnd) {
      canvas.drawRect(
        Rect.fromLTWH(0, rect.bottom - 3, size.width, 3),
        Paint()..color = lineSolid,
      );
    }

    if (!lane.isSegmentStart) {
      final dashPaint = Paint()
        ..color = lineWhite
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      double x = 8;
      while (x < size.width) {
        canvas.drawLine(Offset(x, rect.top + 0.5), Offset(x + 20, rect.top + 0.5), dashPaint);
        x += 38;
      }
    }

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.8;
    for (int col = 1; col < RoadController.numColumns; col++) {
      final cx = col * engine.columnWidth;
      canvas.drawLine(Offset(cx, rect.top), Offset(cx, rect.bottom), gridPaint);
    }

    for (final rd in lane.roadDecorations) {
      switch (rd.type) {
        case PavementKind.manhole:
          _drawImage(canvas, assets.hatch2, rd.x - 16, rect.center.dy - 16, 32, 32);
        case PavementKind.manhole2:
          _drawImage(canvas, assets.hatch2, rd.x - 16, rect.center.dy - 16, 32, 32);
        case PavementKind.skidMark:
          final skidPaint = Paint()
            ..color = Colors.black.withValues(alpha: 0.12)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            Offset(rd.x - 25, rect.center.dy - 4),
            Offset(rd.x + 25, rect.center.dy + 4),
            skidPaint,
          );
          canvas.drawLine(
            Offset(rd.x - 22, rect.center.dy + 2),
            Offset(rd.x + 22, rect.center.dy + 8),
            skidPaint,
          );
        case PavementKind.crack:
          final crackPaint = Paint()
            ..color = Colors.black.withValues(alpha: 0.10)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;
          final path = Path()
            ..moveTo(rd.x - 12, rect.center.dy - 10)
            ..lineTo(rd.x - 2, rect.center.dy - 2)
            ..lineTo(rd.x + 3, rect.center.dy - 5)
            ..lineTo(rd.x + 8, rect.center.dy + 2)
            ..lineTo(rd.x + 14, rect.center.dy + 8);
          canvas.drawPath(path, crackPaint);
      }
    }

    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    if (lane.movingRight) {
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

  void _drawCoins(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane =
        (engine.cameraLane + size.height / RoadController.laneHeight + 4).ceil();
    final colW = engine.columnWidth;
    final time = engine.menuTime;

    for (int i = minLane; i <= maxLane; i++) {
      final lane = engine.lanes[i];
      if (lane == null) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final coin in lane.coins) {
        if (coin.collected) continue;
        final cx = coin.column * colW + colW / 2;
        final bobOffset = sin(time * 4.5 + coin.column * 1.7 + i * 0.3) * 3.5;

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, laneY + 12),
            width: 20,
            height: 7,
          ),
          Paint()..color = const Color(0x33000000),
        );

        _drawImage(
          canvas,
          assets.hatchCoin,
          cx - 14,
          laneY - 16 + bobOffset,
          28,
          28,
        );

        final shimmer =
            ((sin(time * 6 + coin.column * 2.5) + 1) / 2 * 0.3)
                .clamp(0.0, 0.3);
        canvas.drawCircle(
          Offset(cx, laneY - 2 + bobOffset),
          14,
          Paint()
            ..color = Colors.amber.withValues(alpha: shimmer)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
    }
  }

  void _drawVehicleShadows(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane =
        (engine.cameraLane + size.height / RoadController.laneHeight + 4).ceil();
    final shadowPaint = Paint()..color = const Color(0x55000000);

    for (int i = minLane; i <= maxLane; i++) {
      final lane = engine.lanes[i];
      if (lane == null || lane.isSafe) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final vehicle in lane.vehicles) {
        final img = assets.imageForVehicle(vehicle.type);
        final carH = RoadController.laneHeight * 0.85;
        final aspect = img.width / img.height;
        final carW = carH * aspect;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(vehicle.x + 5, laneY + carH * 0.2),
            width: carW * 0.78,
            height: carH * 0.3,
          ),
          shadowPaint,
        );
      }
    }
  }

  void _drawVehicles(Canvas canvas, Size size) {
    final minLane = (engine.cameraLane - 4).floor();
    final maxLane =
        (engine.cameraLane + size.height / RoadController.laneHeight + 4).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final lane = engine.lanes[i];
      if (lane == null || lane.isSafe) continue;
      final laneY = engine.laneScreenY(i.toDouble());

      for (final vehicle in lane.vehicles) {
        final img = assets.imageForVehicle(vehicle.type);
        final carH = RoadController.laneHeight * 0.85;
        final aspect = img.width / img.height;
        final carW = carH * aspect;

        canvas.save();
        canvas.translate(vehicle.x, laneY);
        canvas.rotate(vehicle.movingRight ? -pi / 2 : pi / 2);
        _drawImage(canvas, img, -carW / 2, -carH / 2, carW, carH);
        canvas.restore();
      }
    }
  }

  void _drawCharacterShadow(Canvas canvas) {
    final laneY = engine.laneScreenY(engine.chickenLane.toDouble());
    final shadowW = engine.columnWidth * 0.6;
    final shadowX = engine.chickenScreenX + 2;
    final shadowY = laneY + engine.columnWidth * 0.1;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shadowX, shadowY),
        width: shadowW,
        height: shadowW * 0.35,
      ),
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  void _drawCharacter(Canvas canvas) {
    final isDead = engine.state == AppPhase.gameOver;
    final skinScale = activeSkin == CharSkinType.classic ? 1.0 : 2.0;
    final charSize = engine.columnWidth * 0.85 * skinScale;
    final half = charSize / 2;

    canvas.save();
    canvas.translate(engine.chickenScreenX, engine.chickenScreenY);

    if (engine.facingDir == -1) {
      canvas.scale(-1, 1);
    } else if (engine.facingDir == 1) {
      canvas.scale(1, 1);
    }

    if (isDead) {
      final img = assets.skinDead(activeSkin);
      final t = engine.deathTimer.clamp(0.0, 1.0);
      canvas.rotate(t * 0.12);
      canvas.scale(1.0 + t * 0.2, 1.0 - t * 0.35);
      _drawImage(canvas, img, -half, -half, charSize, charSize);
    } else {
      final img = assets.skinAlive(activeSkin);
      if (engine.hopProgress >= 1.0 && engine.idleTime > 0.3) {
        final idleT = engine.idleTime - 0.3;
        final breathe = 1.0 + sin(idleT * 2.5) * 0.03;
        canvas.scale(breathe, breathe);
      } else if (engine.hopProgress < 1.0) {
        final squash = 1.0 - sin(engine.hopProgress * pi) * 0.12;
        final stretch = 1.0 + sin(engine.hopProgress * pi) * 0.12;
        canvas.scale(squash, stretch);
      }
      _drawImage(canvas, img, -half, -half, charSize, charSize);
    }

    canvas.restore();
  }

  void _drawDeathOverlay(Canvas canvas, Size size) {
    final flashAlpha = (1.0 - engine.deathTimer * 3).clamp(0.0, 0.4);
    if (flashAlpha > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.red.withValues(alpha: flashAlpha),
      );
    }

    if (engine.deathTimer > 0.15) {
      final featherAlpha = ((engine.deathTimer - 0.15) * 2).clamp(0.0, 0.9);
      const featherSize = 250.0;
      final cx = engine.chickenScreenX + engine.shakeX;
      final cy = engine.chickenScreenY + engine.shakeY;
      final paint = Paint()
        ..colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: featherAlpha),
          BlendMode.modulate,
        );
      final src = Rect.fromLTWH(
          0, 0, assets.feathers.width.toDouble(), assets.feathers.height.toDouble());

      for (int f = 0; f < 3; f++) {
        final angle = engine.deathTimer * (1.5 + f * 0.7);
        final dist = engine.deathTimer * 40 * (f + 1);
        final fx = cx + cos(angle) * dist;
        final fy = cy + sin(angle) * dist - engine.deathTimer * 20;
        final dst = Rect.fromCenter(
            center: Offset(fx, fy),
            width: featherSize * 0.6,
            height: featherSize * 0.6);
        canvas.save();
        canvas.translate(fx, fy);
        canvas.rotate(angle * 0.5);
        canvas.translate(-fx, -fy);
        canvas.drawImageRect(assets.feathers, src, dst, paint);
        canvas.restore();
      }
    }
  }

  void _drawImage(
      Canvas canvas, ui.Image img, double x, double y, double w, double h) {
    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromLTWH(x, y, w, h);
    canvas.drawImageRect(
        img, src, dst, Paint()..filterQuality = FilterQuality.high);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ItemMeta {
  final ui.Image img;
  final double baseSize;
  _ItemMeta(this.img, this.baseSize);
}
