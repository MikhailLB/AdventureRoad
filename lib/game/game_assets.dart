import 'dart:ui' as ui;
import 'package:flutter/services.dart';

enum SkinType { classic, golden, steelwing }

class SkinInfo {
  final SkinType type;
  final String name;
  final String asset;
  final String deadAsset;
  final int price;

  const SkinInfo({
    required this.type,
    required this.name,
    required this.asset,
    required this.deadAsset,
    required this.price,
  });
}

const List<SkinInfo> allSkins = [
  SkinInfo(
    type: SkinType.classic,
    name: 'Classic',
    asset: 'assets/chicken.webp',
    deadAsset: 'assets/cheken_rip.webp',
    price: 0,
  ),
  SkinInfo(
    type: SkinType.golden,
    name: 'Golden',
    asset: 'assets/Golden.webp',
    deadAsset: 'assets/Golden-dead.webp',
    price: 49999,
  ),
  SkinInfo(
    type: SkinType.steelwing,
    name: 'Steelwing',
    asset: 'assets/Steelwing.webp',
    deadAsset: 'assets/Steelwing-dead.webp',
    price: 9999,
  ),
];

class GameAssets {
  static final GameAssets _instance = GameAssets._();
  factory GameAssets() => _instance;
  GameAssets._();

  late ui.Image chicken;
  late ui.Image chickenDead;
  late ui.Image feathers;
  late ui.Image taxi;
  late ui.Image police;
  late ui.Image van;
  late ui.Image fireFighter;
  late ui.Image gameName;
  late ui.Image hatchCoin;
  late ui.Image hatch2;
  late ui.Image barrier;
  late ui.Image tree;
  late ui.Image bush1;
  late ui.Image bush2;
  late ui.Image fanar;

  late ui.Image goldenChicken;
  late ui.Image goldenDead;
  late ui.Image steelwingChicken;
  late ui.Image steelwingDead;

  bool loaded = false;

  Future<void> loadAll() async {
    if (loaded) return;

    final results = await Future.wait([
      _load('assets/chicken.webp'),              // 0
      _load('assets/cheken_rip.webp'),           // 1
      _load('assets/feathers.webp'),             // 2
      _load('assets/Cars/Taxi.webp'),            // 3
      _load('assets/Cars/Police.webp'),          // 4
      _load('assets/Cars/Van.webp'),             // 5
      _load('assets/Cars/FireFighter.webp'),     // 6
      _load('assets/game_name.png'),             // 7
      _load('assets/hatch.png'),                 // 8
      _load('assets/hatch_2.png'),               // 9
      _load('assets/barrier.png'),               // 10
      _load('assets/tree.webp'),                 // 11
      _load('assets/bush1.webp'),                // 12
      _load('assets/bush2.webp'),                // 13
      _load('assets/fanar.png'),                 // 14
      _load('assets/Golden.webp'),               // 15
      _load('assets/Golden-dead.webp'),          // 16
      _load('assets/Steelwing.webp'),              // 17
      _load('assets/Steelwing-dead.webp'),         // 18
    ]);

    chicken = results[0];
    chickenDead = results[1];
    feathers = results[2];
    taxi = results[3];
    police = results[4];
    van = results[5];
    fireFighter = results[6];
    gameName = results[7];
    hatchCoin = results[8];
    hatch2 = results[9];
    barrier = results[10];
    tree = results[11];
    bush1 = results[12];
    bush2 = results[13];
    fanar = results[14];
    goldenChicken = results[15];
    goldenDead = results[16];
    steelwingChicken = results[17];
    steelwingDead = results[18];

    loaded = true;
  }

  ui.Image skinAlive(SkinType skin) {
    switch (skin) {
      case SkinType.classic:
        return chicken;
      case SkinType.golden:
        return goldenChicken;
      case SkinType.steelwing:
        return steelwingChicken;
    }
  }

  ui.Image skinDead(SkinType skin) {
    switch (skin) {
      case SkinType.classic:
        return chickenDead;
      case SkinType.golden:
        return goldenDead;
      case SkinType.steelwing:
        return steelwingDead;
    }
  }

  ui.Image imageForVehicle(VehicleType type) {
    switch (type) {
      case VehicleType.taxi:
        return taxi;
      case VehicleType.police:
        return police;
      case VehicleType.van:
        return van;
      case VehicleType.fireFighter:
        return fireFighter;
    }
  }

  Future<ui.Image> _load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

enum VehicleType { taxi, police, van, fireFighter }
