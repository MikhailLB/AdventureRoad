import 'dart:math';
import 'game_assets.dart';

enum GameState { menu, playing, paused, gameOver }

enum DecoType {
  tree, bush1, bush2, barrier, fanar,
}

enum RoadDecoType { manhole, manhole2, skidMark, crack }


class Vehicle {
  final VehicleType type;
  double x;
  final double speed;
  final bool movingRight;

  Vehicle({
    required this.type,
    required this.x,
    required this.speed,
    required this.movingRight,
  });

  double get hitboxWidth {
    switch (type) {
      case VehicleType.fireFighter:
        return 95;
      case VehicleType.van:
        return 80;
      default:
        return 70;
    }
  }
}

class Deco {
  final DecoType type;
  final double x;
  final double scale;
  final bool flipX;
  Deco(this.type, this.x, [this.scale = 1.0, this.flipX = false]);

  double get effectiveWidth {
    const baseSizes = {
      DecoType.tree: 58.0,
      DecoType.bush1: 48.0,
      DecoType.bush2: 46.0,
      DecoType.barrier: 44.0,
      DecoType.fanar: 32.0,
    };
    return (baseSizes[type] ?? 40) * scale;
  }

}

class RoadDeco {
  final RoadDecoType type;
  final double x;
  RoadDeco(this.type, this.x);
}

class Coin {
  final int column;
  bool collected = false;
  Coin(this.column);
}

class LaneData {
  final int index;
  final bool isSafe;
  final bool movingRight;
  final double speed;
  final List<Vehicle> vehicles = [];
  final List<Deco> decorations = [];
  final List<RoadDeco> roadDecorations = [];
  final List<Coin> coins = [];
  double spawnTimer;
  double spawnInterval;
  bool isSegmentStart;
  bool isSegmentEnd;

  LaneData({
    required this.index,
    this.isSafe = false,
    this.movingRight = true,
    this.speed = 100,
    this.spawnInterval = 1.5,
    double? initialSpawnTimer,
    this.isSegmentStart = false,
    this.isSegmentEnd = false,
  }) : spawnTimer = initialSpawnTimer ?? 0;
}

class _DecoSlot {
  final DecoType type;
  final double normX;
  final double scale;
  final bool flipX;
  const _DecoSlot(this.type, this.normX, [this.scale = 1.0, this.flipX = false]);
}

const List<List<_DecoSlot>> _patterns = [
  [_DecoSlot(DecoType.fanar, 0.08, 1.0, true), _DecoSlot(DecoType.bush1, 0.5), _DecoSlot(DecoType.fanar, 0.92)],
  [_DecoSlot(DecoType.tree, 0.2, 1.05), _DecoSlot(DecoType.barrier, 0.75)],
  [_DecoSlot(DecoType.bush2, 0.15), _DecoSlot(DecoType.bush1, 0.5, 0.95), _DecoSlot(DecoType.bush2, 0.85)],
  [_DecoSlot(DecoType.fanar, 0.1, 1.0, true), _DecoSlot(DecoType.tree, 0.4, 1.1), _DecoSlot(DecoType.bush1, 0.72)],
  [_DecoSlot(DecoType.tree, 0.5, 1.15)],
  [_DecoSlot(DecoType.barrier, 0.18), _DecoSlot(DecoType.bush2, 0.5, 1.0), _DecoSlot(DecoType.barrier, 0.82)],
  [_DecoSlot(DecoType.bush1, 0.15, 0.9), _DecoSlot(DecoType.tree, 0.38, 1.0), _DecoSlot(DecoType.bush2, 0.62, 0.9)],
  [_DecoSlot(DecoType.tree, 0.25, 1.0), _DecoSlot(DecoType.tree, 0.75, 0.95)],
  [_DecoSlot(DecoType.fanar, 0.12, 1.0, true), _DecoSlot(DecoType.fanar, 0.88)],
  [_DecoSlot(DecoType.barrier, 0.1), _DecoSlot(DecoType.tree, 0.35, 1.05), _DecoSlot(DecoType.bush1, 0.6), _DecoSlot(DecoType.fanar, 0.88)],
  [],
  [_DecoSlot(DecoType.bush1, 0.3, 1.05)],
  [_DecoSlot(DecoType.fanar, 0.05, 1.0, true), _DecoSlot(DecoType.barrier, 0.45), _DecoSlot(DecoType.fanar, 0.95)],
  [_DecoSlot(DecoType.bush2, 0.18, 0.85), _DecoSlot(DecoType.tree, 0.45, 1.1), _DecoSlot(DecoType.bush1, 0.78, 0.85)],
  [_DecoSlot(DecoType.barrier, 0.22), _DecoSlot(DecoType.bush2, 0.5, 0.9), _DecoSlot(DecoType.barrier, 0.78)],
];

class GameEngine {
  static const double laneHeight = 80.0;
  static const int numColumns = 5;
  static const int _belowLanes = 4;
  static const double metersPerLane = 2.5;

  final Random _rng = Random();

  double screenWidth = 0;
  double screenHeight = 0;
  double get columnWidth => screenWidth / numColumns;

  GameState state = GameState.menu;
  int score = 0;
  int highScore = 0;
  int collectedCoins = 0;
  int bestDistance = 0;
  double multiplier = 1.0;
  int stepsTaken = 0;
  double idleTime = 0;
  int facingDir = 0; // -1 left, 0 forward, 1 right

  int chickenLane = 0;
  int chickenCol = 2;
  int _prevLane = 0;
  int _prevCol = 2;
  double hopProgress = 1.0;
  static const double _hopSpeed = 7.0;

  double cameraLane = 0.0;
  double deathTimer = 0;
  double shakeIntensity = 0;
  double shakeX = 0;
  double shakeY = 0;
  double menuTime = 0;

  int get distance => (chickenLane * metersPerLane).round();

  final Map<int, LaneData> lanes = {};
  int _maxGenerated = -999;

  void setSize(double w, double h) {
    screenWidth = w;
    screenHeight = h;
  }

  void startGame() {
    state = GameState.playing;
    score = 0;
    collectedCoins = 0;
    multiplier = 1.0;
    stepsTaken = 0;
    idleTime = 0;
    chickenLane = 0;
    chickenCol = 2;
    _prevLane = 0;
    _prevCol = 2;
    hopProgress = 1.0;
    cameraLane = 0;
    deathTimer = 0;
    shakeIntensity = 0;
    lanes.clear();
    _maxGenerated = -999;
    _generateBelowLanes();
    _generateUpTo(35);
    _preSpawnVehicles();
  }

  void returnToMenu() {
    state = GameState.menu;
    lanes.clear();
    _maxGenerated = -999;
    chickenLane = 0;
    chickenCol = 2;
    _prevLane = 0;
    _prevCol = 2;
    hopProgress = 1.0;
    cameraLane = 0;
    deathTimer = 0;
    shakeIntensity = 0;
    shakeX = 0;
    shakeY = 0;
  }

  void togglePause() {
    if (state == GameState.playing) {
      state = GameState.paused;
    } else if (state == GameState.paused) {
      state = GameState.playing;
    }
  }

  void _generateBelowLanes() {
    for (int i = -_belowLanes; i < 0; i++) {
      lanes[i] = _safeLane(i);
    }
  }

  void _generateUpTo(int target) {
    final start = _maxGenerated == -999 ? 0 : _maxGenerated + 1;
    for (int i = start; i <= target; i++) {
      lanes[i] = _createLane(i);
    }
    _maxGenerated = target;
  }

  LaneData _createLane(int index) {
    if (index <= 1) return _safeLane(index);

    final adjusted = index - 2;
    final segmentSize = _segmentSizeForDifficulty(index);
    final safeGap = index < 15 ? 2 : (index < 40 ? 2 : 1);
    final cycleLength = segmentSize + safeGap;
    final posInCycle = adjusted % cycleLength;

    if (posInCycle >= segmentSize) return _safeLane(index);

    final difficulty = (index / 50.0).clamp(0.0, 1.0);
    final baseSpeed = 80 + difficulty * 220;
    final speed = baseSpeed + _rng.nextDouble() * 40 - 20;
    final movingRight = posInCycle.isEven;

    final minInterval = (2.0 - difficulty * 1.0).clamp(0.7, 2.0);
    final maxInterval = (3.2 - difficulty * 1.2).clamp(1.4, 3.2);
    final interval = minInterval + _rng.nextDouble() * (maxInterval - minInterval);

    final lane = LaneData(
      index: index,
      isSafe: false,
      movingRight: movingRight,
      speed: speed,
      spawnInterval: interval,
      initialSpawnTimer: _rng.nextDouble() * interval,
      isSegmentStart: posInCycle == 0,
      isSegmentEnd: posInCycle == segmentSize - 1,
    );

    if (_rng.nextDouble() < 0.3) {
      final rdType = RoadDecoType.values[_rng.nextInt(RoadDecoType.values.length)];
      lane.roadDecorations.add(RoadDeco(rdType, 40 + _rng.nextDouble() * (screenWidth - 80)));
    }

    if (_rng.nextDouble() < 0.35) {
      final numCoins = 1 + _rng.nextInt(2);
      final usedCols = <int>{};
      for (int c = 0; c < numCoins; c++) {
        final col = _rng.nextInt(numColumns);
        if (usedCols.add(col)) {
          lane.coins.add(Coin(col));
        }
      }
    }

    return lane;
  }

  int _segmentSizeForDifficulty(int laneIndex) {
    if (laneIndex < 8) return 2;
    if (laneIndex < 20) return 3;
    if (laneIndex < 40) return 4;
    return 4 + _rng.nextInt(2);
  }

  LaneData _safeLane(int index) {
    final lane = LaneData(index: index, isSafe: true);
    if (screenWidth <= 0) return lane;

    final pattern = _patterns[_rng.nextInt(_patterns.length)];
    final mirror = _rng.nextBool();
    final scaleJitter = 0.9 + _rng.nextDouble() * 0.15;

    for (final slot in pattern) {
      var normX = slot.normX;
      if (mirror) normX = 1.0 - normX;
      final x = 20 + normX * (screenWidth - 40);
      final scale = slot.scale * scaleJitter;
      final flip = slot.type == DecoType.fanar ? slot.flipX ^ mirror : false;
      lane.decorations.add(Deco(slot.type, x, scale, flip));
    }
    return lane;
  }

  void _preSpawnVehicles() {
    for (final entry in lanes.entries) {
      final lane = entry.value;
      if (lane.isSafe) continue;

      final numCars = 1 + _rng.nextInt(2);
      for (int c = 0; c < numCars; c++) {
        final type = VehicleType.values[_rng.nextInt(VehicleType.values.length)];
        final x = 60 + _rng.nextDouble() * (screenWidth - 120);

        final tooClose = lane.vehicles.any((v) => (v.x - x).abs() < 180);
        if (tooClose) continue;

        lane.vehicles.add(Vehicle(
          type: type,
          x: x,
          speed: lane.speed * (0.9 + _rng.nextDouble() * 0.2),
          movingRight: lane.movingRight,
        ));
      }
    }
  }

  double laneScreenY(double laneIndex) {
    final anchorY = screenHeight * 0.88;
    return anchorY - (laneIndex - cameraLane) * laneHeight + shakeY;
  }

  double get chickenScreenX {
    final tgtX = chickenCol * columnWidth + columnWidth / 2;
    final prvX = _prevCol * columnWidth + columnWidth / 2;
    return prvX + (tgtX - prvX) * hopProgress + shakeX;
  }

  double get chickenScreenY {
    final tgtLane = chickenLane.toDouble();
    final prvLane = _prevLane.toDouble();
    final animLane = prvLane + (tgtLane - prvLane) * hopProgress;
    final baseY = laneScreenY(animLane);
    final arc = sin(hopProgress * pi) * laneHeight * 0.35;
    return baseY - arc;
  }

  int get coinReward => (collectedCoins * multiplier).round();

  void _collectCoins() {
    final lane = lanes[chickenLane];
    if (lane == null) return;
    for (final coin in lane.coins) {
      if (!coin.collected && coin.column == chickenCol) {
        coin.collected = true;
        collectedCoins += 5;
      }
    }
  }

  void update(double dt) {
    menuTime += dt;

    if (state == GameState.gameOver) {
      deathTimer += dt;
      shakeIntensity *= 0.92;
      shakeX = ((_rng.nextDouble() - 0.5) * 2) * shakeIntensity;
      shakeY = ((_rng.nextDouble() - 0.5) * 2) * shakeIntensity;
      _updateVehicles(dt * 0.15);
      return;
    }
    if (state != GameState.playing) return;

    if (chickenLane + 20 > _maxGenerated) {
      _generateUpTo(_maxGenerated + 25);
      _preSpawnNewLanes();
    }

    cameraLane += (chickenLane.toDouble() - cameraLane) * 5.0 * dt;

    if (hopProgress >= 1.0) {
      idleTime += dt;
    }

    if (hopProgress < 1.0) {
      hopProgress = (hopProgress + _hopSpeed * dt).clamp(0.0, 1.0);
      if (hopProgress >= 1.0) {
        _prevLane = chickenLane;
        _prevCol = chickenCol;
        idleTime = 0;
        _collectCoins();
        if (_checkCollision()) {
          _die();
          return;
        }
      }
    }

    _updateVehicles(dt);
    _spawnVehicles(dt);

    if (hopProgress >= 1.0 && _checkCollision()) {
      _die();
    }
  }

  void _preSpawnNewLanes() {
    final startLane = _maxGenerated - 24;
    for (int i = startLane; i <= _maxGenerated; i++) {
      final lane = lanes[i];
      if (lane == null || lane.isSafe || lane.vehicles.isNotEmpty) continue;
      final type = VehicleType.values[_rng.nextInt(VehicleType.values.length)];
      lane.vehicles.add(Vehicle(
        type: type,
        x: _rng.nextDouble() * screenWidth,
        speed: lane.speed * (0.9 + _rng.nextDouble() * 0.2),
        movingRight: lane.movingRight,
      ));
    }
  }

  void _updateVehicles(double dt) {
    final minLane = (cameraLane - 6).floor();
    final maxLane = (cameraLane + screenHeight / laneHeight + 6).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final lane = lanes[i];
      if (lane == null || lane.isSafe) continue;
      lane.vehicles.removeWhere((v) {
        v.x += (v.movingRight ? v.speed : -v.speed) * dt;
        return v.x < -200 || v.x > screenWidth + 200;
      });
    }
  }

  void _spawnVehicles(double dt) {
    final minLane = (cameraLane - 3).floor();
    final maxLane = (cameraLane + screenHeight / laneHeight + 3).ceil();

    for (int i = minLane; i <= maxLane; i++) {
      final lane = lanes[i];
      if (lane == null || lane.isSafe) continue;

      lane.spawnTimer += dt;
      if (lane.spawnTimer < lane.spawnInterval) continue;
      lane.spawnTimer = 0;

      if (lane.vehicles.length >= 2) continue;

      final type = VehicleType.values[_rng.nextInt(VehicleType.values.length)];
      final startX = lane.movingRight ? -90.0 : screenWidth + 90;

      final tooClose = lane.vehicles.any((v) => (v.x - startX).abs() < 160);
      if (tooClose) continue;

      lane.vehicles.add(Vehicle(
        type: type,
        x: startX,
        speed: lane.speed * (0.9 + _rng.nextDouble() * 0.2),
        movingRight: lane.movingRight,
      ));
    }
  }

  bool _checkCollision() {
    final lane = lanes[chickenLane];
    if (lane == null || lane.isSafe) return false;

    final cx = chickenCol * columnWidth + columnWidth / 2;
    final chickenHalfW = columnWidth * 0.3;

    for (final v in lane.vehicles) {
      final vHalfW = v.hitboxWidth / 2;
      if ((cx - v.x).abs() < chickenHalfW + vHalfW) {
        return true;
      }
    }
    return false;
  }

  void _die() {
    state = GameState.gameOver;
    deathTimer = 0;
    shakeIntensity = 18;
    if (score > highScore) highScore = score;
    if (distance > bestDistance) bestDistance = distance;
  }

  void moveForward() {
    if (state != GameState.playing || hopProgress < 1.0) return;
    _prevLane = chickenLane;
    _prevCol = chickenCol;
    chickenLane++;
    hopProgress = 0.0;
    stepsTaken++;
    multiplier = 1.0 + stepsTaken * 0.05;
    score += (10 * multiplier).round();
    facingDir = 0;
    idleTime = 0;
  }

  void moveBackward() {
    if (state != GameState.playing || hopProgress < 1.0) return;
    if (chickenLane <= 0) return;
    _prevLane = chickenLane;
    _prevCol = chickenCol;
    chickenLane--;
    hopProgress = 0.0;
    facingDir = 0;
    idleTime = 0;
  }

  void moveLeft() {
    if (state != GameState.playing || hopProgress < 1.0) return;
    if (chickenCol <= 0) return;
    _prevCol = chickenCol;
    _prevLane = chickenLane;
    chickenCol--;
    hopProgress = 0.0;
    facingDir = -1;
    idleTime = 0;
  }

  void moveRight() {
    if (state != GameState.playing || hopProgress < 1.0) return;
    if (chickenCol >= numColumns - 1) return;
    _prevCol = chickenCol;
    _prevLane = chickenLane;
    chickenCol++;
    hopProgress = 0.0;
    facingDir = 1;
    idleTime = 0;
  }
}
