import 'dart:ui' as ui;
import 'package:flutter/services.dart';

enum CharSkinType { classic, golden, steelwing }

class CharacterSkin {
  final CharSkinType type;
  final String name;
  final String asset;
  final String deadAsset;
  final int price;

  const CharacterSkin({
    required this.type,
    required this.name,
    required this.asset,
    required this.deadAsset,
    required this.price,
  });
}

const List<CharacterSkin> allCharSkins = [
  CharacterSkin(
    type: CharSkinType.classic,
    name: 'Classic',
    asset: 'assets/chicken.webp',
    deadAsset: 'assets/cheken_rip.webp',
    price: 0,
  ),
  CharacterSkin(
    type: CharSkinType.golden,
    name: 'Golden',
    asset: 'assets/Golden.webp',
    deadAsset: 'assets/Golden-dead.webp',
    price: 49999,
  ),
  CharacterSkin(
    type: CharSkinType.steelwing,
    name: 'Steelwing',
    asset: 'assets/Steelwing.webp',
    deadAsset: 'assets/Steelwing-dead.webp',
    price: 9999,
  ),
];

class MediaBundle {
  static final MediaBundle _instance = MediaBundle._();
  factory MediaBundle() => _instance;
  MediaBundle._();

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
      _load('assets/chicken.webp'),
      _load('assets/cheken_rip.webp'),
      _load('assets/feathers.webp'),
      _load('assets/Cars/Taxi.webp'),
      _load('assets/Cars/Police.webp'),
      _load('assets/Cars/Van.webp'),
      _load('assets/Cars/FireFighter.webp'),
      _load('assets/game_name.png'),
      _load('assets/hatch.png'),
      _load('assets/hatch_2.png'),
      _load('assets/barrier.png'),
      _load('assets/tree.webp'),
      _load('assets/bush1.webp'),
      _load('assets/bush2.webp'),
      _load('assets/fanar.png'),
      _load('assets/Golden.webp'),
      _load('assets/Golden-dead.webp'),
      _load('assets/Steelwing.webp'),
      _load('assets/Steelwing-dead.webp'),
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

  ui.Image skinAlive(CharSkinType skin) {
    switch (skin) {
      case CharSkinType.classic:
        return chicken;
      case CharSkinType.golden:
        return goldenChicken;
      case CharSkinType.steelwing:
        return steelwingChicken;
    }
  }

  ui.Image skinDead(CharSkinType skin) {
    switch (skin) {
      case CharSkinType.classic:
        return chickenDead;
      case CharSkinType.golden:
        return goldenDead;
      case CharSkinType.steelwing:
        return steelwingDead;
    }
  }

  ui.Image imageForVehicle(TrafficKind type) {
    switch (type) {
      case TrafficKind.taxi:
        return taxi;
      case TrafficKind.police:
        return police;
      case TrafficKind.van:
        return van;
      case TrafficKind.fireFighter:
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

enum TrafficKind { taxi, police, van, fireFighter }
