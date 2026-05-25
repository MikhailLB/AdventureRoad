import 'dart:ui' as ui;
import 'package:flutter/services.dart';

enum HeroVariant { classic, gold, chrome, zombie }

class HeroInfo {
  final HeroVariant type;
  final String name;
  final String asset;
  final String deadAsset;
  final int price;

  const HeroInfo({
    required this.type,
    required this.name,
    required this.asset,
    required this.deadAsset,
    required this.price,
  });
}

const List<HeroInfo> allHeroes = [
  HeroInfo(
    type: HeroVariant.classic,
    name: 'Droid',
    asset: 'assets/droid_run.webp',
    deadAsset: 'assets/droid_smash.webp',
    price: 0,
  ),
  HeroInfo(
    type: HeroVariant.gold,
    name: 'Gold Droid',
    asset: 'assets/droid_gold.webp',
    deadAsset: 'assets/droid_gold_smash.webp',
    price: 49999,
  ),
  HeroInfo(
    type: HeroVariant.chrome,
    name: 'Chrome Droid',
    asset: 'assets/droid_chrome.webp',
    deadAsset: 'assets/droid_chrome_smash.webp',
    price: 9999,
  ),
  HeroInfo(
    type: HeroVariant.zombie,
    name: 'Zombie Droid',
    asset: 'assets/droid_zombie.webp',
    deadAsset: 'assets/droid_zombie_smash.webp',
    price: 19999,
  ),
];

class SceneAssets {
  static final SceneAssets _instance = SceneAssets._();
  factory SceneAssets() => _instance;
  SceneAssets._();

  late ui.Image droid;
  late ui.Image droidSmash;
  late ui.Image sparks;
  late ui.Image hoverCab;
  late ui.Image hoverPatrol;
  late ui.Image hoverCargo;
  late ui.Image hoverRescue;
  late ui.Image titleLogo;
  late ui.Image chipCoin;
  late ui.Image chipCoinAlt;
  late ui.Image propBarrier;
  late ui.Image propTower;
  late ui.Image propNodeA;
  late ui.Image propNodeB;
  late ui.Image propLamp;

  late ui.Image droidGold;
  late ui.Image droidGoldSmash;
  late ui.Image droidChrome;
  late ui.Image droidChromeSmash;
  late ui.Image droidZombie;
  late ui.Image droidZombieSmash;

  bool loaded = false;

  Future<void> loadAll() async {
    if (loaded) return;

    final results = await Future.wait([
      _load('assets/droid_run.webp'),          // 0
      _load('assets/droid_smash.webp'),        // 1
      _load('assets/sparks.webp'),             // 2
      _load('assets/Cars/hover_cab.webp'),     // 3
      _load('assets/Cars/hover_patrol.webp'),  // 4
      _load('assets/Cars/hover_cargo.webp'),   // 5
      _load('assets/Cars/hover_rescue.webp'),  // 6
      _load('assets/chrome_rush_title.png'),   // 7
      _load('assets/chip_coin.png'),           // 8
      _load('assets/chip_coin_alt.png'),       // 9
      _load('assets/prop_barrier.png'),        // 10
      _load('assets/prop_tower.webp'),         // 11
      _load('assets/prop_node_a.webp'),        // 12
      _load('assets/prop_node_b.webp'),        // 13
      _load('assets/prop_lamp.png'),           // 14
      _load('assets/droid_gold.webp'),         // 15
      _load('assets/droid_gold_smash.webp'),   // 16
      _load('assets/droid_chrome.webp'),        // 17
      _load('assets/droid_chrome_smash.webp'),  // 18
      _load('assets/droid_zombie.webp'),        // 19
      _load('assets/droid_zombie_smash.webp'),  // 20
    ]);

    droid = results[0];
    droidSmash = results[1];
    sparks = results[2];
    hoverCab = results[3];
    hoverPatrol = results[4];
    hoverCargo = results[5];
    hoverRescue = results[6];
    titleLogo = results[7];
    chipCoin = results[8];
    chipCoinAlt = results[9];
    propBarrier = results[10];
    propTower = results[11];
    propNodeA = results[12];
    propNodeB = results[13];
    propLamp = results[14];
    droidGold = results[15];
    droidGoldSmash = results[16];
    droidChrome = results[17];
    droidChromeSmash = results[18];
    droidZombie = results[19];
    droidZombieSmash = results[20];

    loaded = true;
  }

  ui.Image heroAlive(HeroVariant v) {
    switch (v) {
      case HeroVariant.classic:
        return droid;
      case HeroVariant.gold:
        return droidGold;
      case HeroVariant.chrome:
        return droidChrome;
      case HeroVariant.zombie:
        return droidZombie;
    }
  }

  ui.Image heroDead(HeroVariant v) {
    switch (v) {
      case HeroVariant.classic:
        return droidSmash;
      case HeroVariant.gold:
        return droidGoldSmash;
      case HeroVariant.chrome:
        return droidChromeSmash;
      case HeroVariant.zombie:
        return droidZombieSmash;
    }
  }

  ui.Image imageForHazard(HazardType type) {
    switch (type) {
      case HazardType.cab:
        return hoverCab;
      case HazardType.patrol:
        return hoverPatrol;
      case HazardType.cargo:
        return hoverCargo;
      case HazardType.rescuer:
        return hoverRescue;
    }
  }

  Future<ui.Image> _load(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

enum HazardType { cab, patrol, cargo, rescuer }
