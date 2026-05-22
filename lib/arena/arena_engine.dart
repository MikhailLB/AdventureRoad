import 'dart:math';
import 'scene_assets.dart';

enum ArenaState { menu, playing, paused, gameOver }

enum PropType {
  tower, nodeA, nodeB, barrier, lamp,
}

enum SurfaceDecoType { panel, panel2, skidMark, crack }

class Hazard {
  final HazardType type;
  double x;
  final double speed;
  final bool movingRight;

  Hazard({
    required this.type,
    required this.x,
    required this.speed,
    required this.movingRight,
  });

  double get hitboxWidth {
    switch (type) {
      case HazardType.rescuer:
        return 95;
      case HazardType.cargo:
        return 80;
      default:
        return 70;
    }
  }
}

class Prop {
  final PropType type;
  final double x;
  final double scale;
  final bool flipX;
  Prop(this.type, this.x, [this.scale = 1.0, this.flipX = false]);

  double get effectiveWidth {
    const baseSizes = {
      PropType.tower: 58.0,
      PropType.nodeA: 48.0,
      PropType.nodeB: 46.0,
      PropType.barrier: 44.0,
      PropType.lamp: 32.0,
    };
    return (baseSizes[type] ?? 40) * scale;
  }
}

class SurfaceDeco {
  final SurfaceDecoType type;
  final double x;
  SurfaceDeco(this.type, this.x);
}

class Chip {
  final int column;
  bool collected = false;
  Chip(this.column);
}

class GridRow {
  final int index;
  final bool isSafe;
  final bool movingRight;
  final double speed;
  final bool isTurbo;
  final List<Hazard> vehicles = [];
  final List<Prop> decorations = [];
  final List<SurfaceDeco> surfaceDecos = [];
  final List<Chip> chips = [];
  double spawnTimer;
  double spawnInterval;
  bool isSegmentStart;
  bool isSegmentEnd;

  GridRow({
    required this.index,
    this.isSafe = false,
    this.movingRight = true,
    this.speed = 100,
    this.spawnInterval = 1.5,
    this.isTurbo = false,
    double? initialSpawnTimer,
    this.isSegmentStart = false,
    this.isSegmentEnd = false,
  }) : spawnTimer = initialSpawnTimer ?? 0;
}

class _PropSlot {
  final PropType type;
  final double normX;
  final double scale;
  final bool flipX;
  const _PropSlot(this.type, this.normX, [this.scale = 1.0, this.flipX = false]);
}

const List<List<_PropSlot>> _propPatterns = [
  [_PropSlot(PropType.lamp, 0.08, 1.0, true), _PropSlot(PropType.nodeA, 0.5), _PropSlot(PropType.lamp, 0.92)],
  [_PropSlot(PropType.tower, 0.2, 1.05), _PropSlot(PropType.barrier, 0.75)],
  [_PropSlot(PropType.nodeB, 0.15), _PropSlot(PropType.nodeA, 0.5, 0.95), _PropSlot(PropType.nodeB, 0.85)],
  [_PropSlot(PropType.lamp, 0.1, 1.0, true), _PropSlot(PropType.tower, 0.4, 1.1), _PropSlot(PropType.nodeA, 0.72)],
  [_PropSlot(PropType.tower, 0.5, 1.15)],
  [_PropSlot(PropType.barrier, 0.18), _PropSlot(PropType.nodeB, 0.5, 1.0), _PropSlot(PropType.barrier, 0.82)],
  [_PropSlot(PropType.nodeA, 0.15, 0.9), _PropSlot(PropType.tower, 0.38, 1.0), _PropSlot(PropType.nodeB, 0.62, 0.9)],
  [_PropSlot(PropType.tower, 0.25, 1.0), _PropSlot(PropType.tower, 0.75, 0.95)],
  [_PropSlot(PropType.lamp, 0.12, 1.0, true), _PropSlot(PropType.lamp, 0.88)],
  [_PropSlot(PropType.barrier, 0.1), _PropSlot(PropType.tower, 0.35, 1.05), _PropSlot(PropType.nodeA, 0.6), _PropSlot(PropType.lamp, 0.88)],
  [],
  [_PropSlot(PropType.nodeA, 0.3, 1.05)],
  [_PropSlot(PropType.lamp, 0.05, 1.0, true), _PropSlot(PropType.barrier, 0.45), _PropSlot(PropType.lamp, 0.95)],
  [_PropSlot(PropType.nodeB, 0.18, 0.85), _PropSlot(PropType.tower, 0.45, 1.1), _PropSlot(PropType.nodeA, 0.78, 0.85)],
  [_PropSlot(PropType.barrier, 0.22), _PropSlot(PropType.nodeB, 0.5, 0.9), _PropSlot(PropType.barrier, 0.78)],
];

class ArenaEngine {
  static const double laneHeight = 80.0;
  static const int numColumns = 6;
  static const int _belowLanes = 4;
  static const double metersPerLane = 2.5;

  final Random _rng = Random();

  double screenWidth = 0;
  double screenHeight = 0;
  double get columnWidth => screenWidth / numColumns;

  ArenaState state = ArenaState.menu;
  int score = 0;
  int highScore = 0;
  int collectedCoins = 0;
  int bestDistance = 0;
  double multiplier = 1.0;
  int stepsTaken = 0;
  double idleTime = 0;
  int facingDir = 0; // -1 left, 0 forward, 1 right

  // Combo system
  int coinStreak = 0;
  bool get comboActive => coinStreak >= 3;

  int heroLane = 0;
  int heroCol = 3; // center of 6 columns
  int _prevLane = 0;
  int _prevCol = 3;
  double hopProgress = 1.0;
  static const double _hopSpeed = 7.0;

  double cameraLane = 0.0;
  double deathTimer = 0;
  double shakeIntensity = 0;
  double shakeX = 0;
  double shakeY = 0;
  double menuTime = 0;

  int get distance => (heroLane * metersPerLane).round();
  int get coinReward => (collectedCoins * multiplier).round();

  final Map<int, GridRow> lanes = {};
  int _maxGenerated = -999;

  void setSize(double w, double h) {
    screenWidth = w;
    screenHeight = h;
  }

  void startGame() {
    state = ArenaState.playing;
    score = 0;
    collectedCoins = 0;
    multiplier = 1.0;
    stepsTaken = 0;
    idleTime = 0;
    coinStreak = 0;
    heroLane = 0;
    heroCol = 3;
    _prevLane = 0;
    _prevCol = 3;
    hopProgress = 1.0;
    cameraLane = 0;
    deathTimer = 0;
    shakeIntensity = 0;
    lanes.clear();
    _maxGenerated = -999;
    _generateBelowLanes();
    _generateUpTo(35);
    _preSpawnHazards();
  }

  void returnToMenu() {
    state = ArenaState.menu;
    lanes.clear();
    _maxGenerated = -999;
    heroLane = 0;
    heroCol = 3;
    _prevLane = 0;
    _prevCol = 3;
    hopProgress = 1.0;
    cameraLane = 0;
    deathTimer = 0;
    shakeIntensity = 0;
    shakeX = 0;
    shakeY = 0;
  }

  void togglePause() {
    if (state == ArenaState.playing) {
      state = ArenaState.paused;
    } else if (state == ArenaState.paused) {
      state = ArenaState.playing;
    }
  }

  void _generateBelowLanes() {
    for (int i = -_belowLanes; i < 0; i++) {
      lanes[i] = _safeRow(i);
    }
  }

  void _generateUpTo(int target) {
    final start = _maxGenerated == -999 ? 0 : _maxGenerated + 1;
    for (int i = start; i <= target; i++) {
      lanes[i] = _createRow(i);
    }
    _maxGenerated = target;
  }

  GridRow _createRow(int index) {
    if (index <= 1) return _safeRow(index);

    final adjusted = index - 2;
    final segmentSize = _segmentSizeForDifficulty(index);
    final safeGap = index < 15 ? 2 : (index < 40 ? 2 : 1);
    final cycleLength = segmentSize + safeGap;
    final posInCycle = adjusted % cycleLength;

    if (posInCycle >= segmentSize) return _safeRow(index);

    final difficulty = (index / 50.0).clamp(0.0, 1.0);
    final baseSpeed = 80 + difficulty * 220;
    final speed = baseSpeed + _rng.nextDouble() * 40 - 20;
    final movingRight = posInCycle.isEven;

    // Turbo lane: every ~15 lanes, mid-segment becomes a turbo row
    final isTurbo = index > 20 && posInCycle == segmentSize ~/ 2;
    final effectiveSpeed = isTurbo ? speed * 1.8 : speed;

    final minInterval = (2.0 - difficulty * 1.0).clamp(0.7, 2.0);
    final maxInterval = (3.2 - difficulty * 1.2).clamp(1.4, 3.2);
    final interval = minInterval + _rng.nextDouble() * (maxInterval - minInterval);

    final row = GridRow(
      index: index,
      isSafe: false,
      movingRight: movingRight,
      speed: effectiveSpeed,
      spawnInterval: interval,
      isTurbo: isTurbo,
      initialSpawnTimer: _rng.nextDouble() * interval,
      isSegmentStart: posInCycle == 0,
      isSegmentEnd: posInCycle == segmentSize - 1,
    );

    if (_rng.nextDouble() < 0.3) {
      final sdType = SurfaceDecoType.values[_rng.nextInt(SurfaceDecoType.values.length)];
      row.surfaceDecos.add(SurfaceDeco(sdType, 40 + _rng.nextDouble() * (screenWidth - 80)));
    }

    // Turbo lanes give 3x chips
    final chipChance = isTurbo ? 0.85 : 0.35;
    if (_rng.nextDouble() < chipChance) {
      final numChips = isTurbo ? 2 : 1 + _rng.nextInt(2);
      final usedCols = <int>{};
      for (int c = 0; c < numChips; c++) {
        final col = _rng.nextInt(numColumns);
        if (usedCols.add(col)) {
          row.chips.add(Chip(col));
        }
      }
    }

    return row;
  }

  int _segmentSizeForDifficulty(int laneIndex) {
    if (laneIndex < 8) return 2;
    if (laneIndex < 20) return 3;
    if (laneIndex < 40) return 4;
    return 4 + _rng.nextInt(2);
  }

  GridRow _safeRow(int index) {
    final row = GridRow(index: index, isSafe: true);
    if (screenWidth <= 0) return row;

    final pattern = _propPatterns[_rng.nextInt(_propPatterns.length)];
    final mirror = _rng.nextBool();
    final scaleJitter = 0.9 + _rng.nextDouble() * 0.15;

    for (final slot in pattern) {
      var normX = slot.normX;
      if (mirror) normX = 1.0 - normX;
      final x = 20 + normX * (screenWidth - 40);
      final scale = slot.scale * scaleJitter;
      final flip = slot.type == PropType.lamp ? slot.flipX ^ mirror : false;
      row.decorations.add(Prop(slot.type, x, scale, flip));
    }
    return row;
  }

  void _preSpawnHazards() {
    for (final entry in lanes.entries) {
      final row = entry.value;
      if (row.isSafe) continue;

      final numH = 1 + _rng.nextInt(2);
      for (int c = 0; c < numH; c++) {
        final type = HazardType.values[_rng.nextInt(HazardType.values.length)];
        final x = 60 + _rng.nextDouble() * (screenWidth - 120);

        final tooClose = row.vehicles.any((v) => (v.x - x).abs() < 180);
        if (tooClose) continue;

        row.vehicles.add(Hazard(
          type: type,
          x: x,
          speed: row.speed * (0.9 + _rng.nextDouble() * 0.2),
          movingRight: row.movingRight,
        ));
      }
    }
  }

  double laneScreenY(double laneIndex) {
    final anchorY = screenHeight * 0.88;
    return anchorY - (laneIndex - cameraLane) * laneHeight + shakeY;
  }

  double get heroScreenX {
    final tgtX = heroCol * columnWidth + columnWidth / 2;
    final prvX = _prevCol * columnWidth + columnWidth / 2;
    return prvX + (tgtX - prvX) * hopProgress + shakeX;
  }

  double get heroScreenY {
    final tgtLane = heroLane.toDouble();
    final prvLane = _prevLane.toDouble();
    final animLane = prvLane + (tgtLane - prvLane) * hopProgress;
    final baseY = laneScreenY(animLane);
    final arc = sin(hopProgress * pi) * laneHeight * 0.35;
    return baseY - arc;
  }

  void _collectChips() {
    final row = lanes[heroLane];
    if (row == null) return;
    for (final chip in row.chips) {
      if (!chip.collected && chip.column == heroCol) {
        chip.collected = true;
        coinStreak++;
        // Turbo lanes give 3x coins; combo gives 1.5x bonus
        final turboBonus = (row.isTurbo) ? 3.0 : 1.0;
        final comboBonus = comboActive ? 1.5 : 1.0;
        collectedCoins += (5 * turboBonus).round();
        score += (18 * multiplier * turboBonus * comboBonus).round();
      }
    }
  }

  void update(double dt) {
    menuTime += dt;

    if (state == ArenaState.gameOver) {
      deathTimer += dt;
      shakeIntensity *= 0.92;
      shakeX = ((_rng.nextDouble() - 0.5) * 2) * shakeIntensity;
      shakeY = ((_rng.nextDouble() - 0.5) * 2) * shakeIntensity;
      _updateHazards(dt * 0.15);
      return;
    }
    if (state != ArenaState.playing) return;

    if (heroLane + 20 > _maxGenerated) {
      _generateUpTo(_maxGenerated + 25);
      _preSpawnNewRows();
    }

    cameraLane += (heroLane.toDouble() - cameraLane) * 5.0 * dt;

    if (hopProgress >= 1.0) {
      idleTime += dt;
    }

    if (hopProgress < 1.0) {
      hopProgress = (hopProgress + _hopSpeed * dt).clamp(0.0, 1.0);
      if (hopProgress >= 1.0) {
        _prevLane = heroLane;
        _prevCol = heroCol;
        idleTime = 0;
        _collectChips();
        if (_checkCollision()) {
          _die();
          return;
        }
      }
    }

    _updateHazards(dt);
    _spawnHazards(dt);

    if (hopProgress >= 1.0 && _checkCollision()) {
      _die();
    }
  }

  void _preSpawnNewRows() {
    final startRow = _maxGenerated - 24;
    for (int i = startRow; i <= _maxGenerated; i++) {
      final row = lanes[i];
      if (row == null || row.isSafe || row.vehicles.isNotEmpty) continue;
      final type = HazardType.values[_rng.nextInt(HazardType.values.length)];
      row.vehicles.add(Hazard(
        type: type,
        x: _rng.nextDouble() * screenWidth,
        speed: row.speed * (0.9 + _rng.nextDouble() * 0.2),
        movingRight: row.movingRight,
      ));
    }
  }

  void _updateHazards(double dt) {
    final minLane = (cameraLane - 6).floor();
    final maxLane = (cameraLane + screenHeight / laneHeight + 6).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final row = lanes[i];
      if (row == null || row.isSafe) continue;
      row.vehicles.removeWhere((v) {
        v.x += (v.movingRight ? v.speed : -v.speed) * dt;
        return v.x < -200 || v.x > screenWidth + 200;
      });
    }
  }

  void _spawnHazards(double dt) {
    final minLane = (cameraLane - 3).floor();
    final maxLane = (cameraLane + screenHeight / laneHeight + 3).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final row = lanes[i];
      if (row == null || row.isSafe) continue;

      row.spawnTimer += dt;
      if (row.spawnTimer < row.spawnInterval) continue;
      row.spawnTimer = 0;

      if (row.vehicles.length >= 2) continue;

      final type = HazardType.values[_rng.nextInt(HazardType.values.length)];
      final startX = row.movingRight ? -90.0 : screenWidth + 90;

      final tooClose = row.vehicles.any((v) => (v.x - startX).abs() < 160);
      if (tooClose) continue;

      row.vehicles.add(Hazard(
        type: type,
        x: startX,
        speed: row.speed * (0.9 + _rng.nextDouble() * 0.2),
        movingRight: row.movingRight,
      ));
    }
  }

  bool _checkCollision() {
    final row = lanes[heroLane];
    if (row == null || row.isSafe) return false;

    final cx = heroCol * columnWidth + columnWidth / 2;
    final heroHalfW = columnWidth * 0.3;

    for (final v in row.vehicles) {
      final vHalfW = v.hitboxWidth / 2;
      if ((cx - v.x).abs() < heroHalfW + vHalfW) {
        return true;
      }
    }
    return false;
  }

  void _die() {
    state = ArenaState.gameOver;
    deathTimer = 0;
    shakeIntensity = 18;
    if (score > highScore) highScore = score;
    if (distance > bestDistance) bestDistance = distance;
  }

  void moveForward() {
    if (state != ArenaState.playing || hopProgress < 1.0) return;
    _prevLane = heroLane;
    _prevCol = heroCol;
    heroLane++;
    hopProgress = 0.0;
    stepsTaken++;
    multiplier = 1.0 + stepsTaken * 0.05;
    score += (10 * multiplier).round();
    facingDir = 0;
    idleTime = 0;
  }

  void moveBackward() {
    if (state != ArenaState.playing || hopProgress < 1.0) return;
    if (heroLane <= 0) return;
    _prevLane = heroLane;
    _prevCol = heroCol;
    heroLane--;
    hopProgress = 0.0;
    facingDir = 0;
    idleTime = 0;
    coinStreak = 0; // reset combo on retreat
  }

  void moveLeft() {
    if (state != ArenaState.playing || hopProgress < 1.0) return;
    if (heroCol <= 0) return;
    _prevCol = heroCol;
    _prevLane = heroLane;
    heroCol--;
    hopProgress = 0.0;
    facingDir = -1;
    idleTime = 0;
  }

  void moveRight() {
    if (state != ArenaState.playing || hopProgress < 1.0) return;
    if (heroCol >= numColumns - 1) return;
    _prevCol = heroCol;
    _prevLane = heroLane;
    heroCol++;
    hopProgress = 0.0;
    facingDir = 1;
    idleTime = 0;
  }
}
