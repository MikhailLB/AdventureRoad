import 'dart:ui' as ui;
import 'package:flutter/services.dart';

enum HeroVariant { classic, gold, chrome }

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
    name: 'Runner',
    asset: 'assets/runner_a.webp',
    deadAsset: 'assets/runner_a_hit.webp',
    price: 0,
  ),
  HeroInfo(
    type: HeroVariant.gold,
    name: 'Gold Runner',
    asset: 'assets/runner_c.webp',
    deadAsset: 'assets/runner_c_hit.webp',
    price: 49999,
  ),
  HeroInfo(
    type: HeroVariant.chrome,
    name: 'Chrome Runner',
    asset: 'assets/runner_b.webp',
    deadAsset: 'assets/runner_b_hit.webp',
    price: 9999,
  ),
];

class SceneAssets {
  static final SceneAssets _instance = SceneAssets._();
  factory SceneAssets() => _instance;
  SceneAssets._();

  late ui.Image runner;
  late ui.Image runnerHit;
  late ui.Image burst;
  late ui.Image vehA;
  late ui.Image vehB;
  late ui.Image vehC;
  late ui.Image vehD;
  late ui.Image titleCard;
  late ui.Image tokenA;
  late ui.Image tokenB;
  late ui.Image envGate;
  late ui.Image envTower;
  late ui.Image envNodeA;
  late ui.Image envNodeB;
  late ui.Image envLight;

  late ui.Image runnerGold;
  late ui.Image runnerGoldHit;
  late ui.Image runnerChrome;
  late ui.Image runnerChromeHit;

  bool loaded = false;

  Future<void> loadAll() async {
    if (loaded) return;

    final results = await Future.wait([
      _load('assets/runner_a.webp'),          // 0
      _load('assets/runner_a_hit.webp'),      // 1
      _load('assets/fx_burst.webp'),          // 2
      _load('assets/vehicles/veh_a.webp'),    // 3
      _load('assets/vehicles/veh_c.webp'),    // 4
      _load('assets/vehicles/veh_b.webp'),    // 5
      _load('assets/vehicles/veh_d.webp'),    // 6
      _load('assets/title_card.webp'),         // 7
      _load('assets/item_token.png'),         // 8
      _load('assets/item_token_alt.png'),     // 9
      _load('assets/env_gate.png'),           // 10
      _load('assets/env_tower.webp'),         // 11
      _load('assets/env_node_a.webp'),        // 12
      _load('assets/env_node_b.webp'),        // 13
      _load('assets/env_light.png'),          // 14
      _load('assets/runner_c.webp'),          // 15
      _load('assets/runner_c_hit.webp'),      // 16
      _load('assets/runner_b.webp'),          // 17
      _load('assets/runner_b_hit.webp'),      // 18
    ]);

    runner = results[0];
    runnerHit = results[1];
    burst = results[2];
    vehA = results[3];
    vehB = results[4];
    vehC = results[5];
    vehD = results[6];
    titleCard = results[7];
    tokenA = results[8];
    tokenB = results[9];
    envGate = results[10];
    envTower = results[11];
    envNodeA = results[12];
    envNodeB = results[13];
    envLight = results[14];
    runnerGold = results[15];
    runnerGoldHit = results[16];
    runnerChrome = results[17];
    runnerChromeHit = results[18];

    loaded = true;
  }

  ui.Image heroAlive(HeroVariant v) {
    switch (v) {
      case HeroVariant.classic:
        return runner;
      case HeroVariant.gold:
        return runnerGold;
      case HeroVariant.chrome:
        return runnerChrome;
    }
  }

  ui.Image heroDead(HeroVariant v) {
    switch (v) {
      case HeroVariant.classic:
        return runnerHit;
      case HeroVariant.gold:
        return runnerGoldHit;
      case HeroVariant.chrome:
        return runnerChromeHit;
    }
  }

  ui.Image imageForHazard(HazardType type) {
    switch (type) {
      case HazardType.cab:
        return vehA;
      case HazardType.patrol:
        return vehC;
      case HazardType.cargo:
        return vehB;
      case HazardType.rescuer:
        return vehD;
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
