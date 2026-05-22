import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cfg/remote_paths.dart';
import '../views/web_page.dart';
import 'media_bundle.dart';
import 'road_controller.dart';
import 'scene_renderer.dart';

class _MockPlayer {
  final String name;
  final int score;
  final int distance;
  final Color color;

  const _MockPlayer(this.name, this.score, this.distance, this.color);
}

final List<_MockPlayer> _mockPlayers = [
  _MockPlayer('SpeedRunner', 847, 210, Colors.redAccent),
  _MockPlayer('UrbanRacer', 723, 185, Colors.blueAccent),
  _MockPlayer('NightDrifter', 612, 162, Colors.teal),
  _MockPlayer('TurboKing', 589, 150, Colors.purple),
  _MockPlayer('DashMaster', 501, 130, Colors.orange),
  _MockPlayer('StormRider', 478, 118, Colors.green),
  _MockPlayer('AsphaltAce', 432, 105, Colors.cyan),
  _MockPlayer('BlazeRunner', 391, 92, Colors.pink),
  _MockPlayer('GridLock', 345, 80, Colors.amber),
  _MockPlayer('PeakShifter', 298, 70, Colors.indigo),
];

class PlayView extends StatefulWidget {
  const PlayView({super.key});

  @override
  State<PlayView> createState() => _PlayViewState();
}

class _PlayViewState extends State<PlayView>
    with SingleTickerProviderStateMixin {
  final RoadController _engine = RoadController();
  final MediaBundle _assets = MediaBundle();
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  String _playerName = 'You';
  int _totalCoins = 0;
  bool _showLeaderboard = false;
  bool _showShop = false;
  bool _coinsSaved = false;
  bool _assetsReady = false;
  String? _loadError;

  CharSkinType _activeSkin = CharSkinType.classic;
  Set<CharSkinType> _ownedSkins = {CharSkinType.classic};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _ticker = createTicker(_onTick);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await _assets.loadAll();
      final prefs = await SharedPreferences.getInstance();
      _engine.highScore = prefs.getInt('pts_best') ?? 0;
      _engine.bestDistance = prefs.getInt('dist_top') ?? 0;
      _totalCoins = prefs.getInt('wallet') ?? 0;
      _playerName = prefs.getString('usr_name') ?? 'You';

      final skinName = prefs.getString('sel_char') ?? 'classic';
      _activeSkin = CharSkinType.values.firstWhere((s) => s.name == skinName,
          orElse: () => CharSkinType.classic);

      final ownedList = prefs.getStringList('chars_owned') ?? ['classic'];
      _ownedSkins = ownedList
          .map((n) => CharSkinType.values.firstWhere((s) => s.name == n,
              orElse: () => CharSkinType.classic))
          .toSet();
      _ownedSkins.add(CharSkinType.classic);

      if (mounted) {
        _assetsReady = true;
        _ticker.start();
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
      });
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pts_best', _engine.highScore);
    await prefs.setInt('dist_top', _engine.bestDistance);
    await prefs.setInt('wallet', _totalCoins);
    await prefs.setString('usr_name', _playerName);
    await prefs.setString('sel_char', _activeSkin.name);
    await prefs.setStringList(
        'chars_owned', _ownedSkins.map((s) => s.name).toList());
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    _engine.update(dt.clamp(0.0, 0.05));

    if (_engine.state == AppPhase.gameOver && !_coinsSaved) {
      _totalCoins += _engine.coinReward;
      _coinsSaved = true;
      _saveData();
    }
    if (_engine.state == AppPhase.playing) {
      _coinsSaved = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  String _skinAssetPath(CharSkinType skin) {
    return allCharSkins.firstWhere((s) => s.type == skin).asset;
  }

  String _skinDeadAssetPath(CharSkinType skin) {
    return allCharSkins.firstWhere((s) => s.type == skin).deadAsset;
  }

  void _buySkin(CharSkinType skin) {
    final info = allCharSkins.firstWhere((s) => s.type == skin);
    if (_ownedSkins.contains(skin)) {
      _activeSkin = skin;
      _saveData();
      setState(() {});
      return;
    }
    if (_totalCoins >= info.price) {
      _totalCoins -= info.price;
      _ownedSkins.add(skin);
      _activeSkin = skin;
      _saveData();
      setState(() {});
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _playerName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A3E),
        title:
            const Text('Player Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 15,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.amber.shade700)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.amber)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child:
                  const Text('Save', style: TextStyle(color: Colors.amber))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      _playerName = result;
      _saveData();
      if (mounted) setState(() {});
    }
  }

  void _handleTap() {
    if (_showLeaderboard || _showShop) return;
    if (_engine.state == AppPhase.menu) {
      _engine.startGame();
    } else if (_engine.state == AppPhase.playing) {
      _engine.moveForward();
    } else if (_engine.state == AppPhase.paused) {
      _engine.togglePause();
    }
  }

  Offset? _dragStart;
  void _onPanStart(DragStartDetails d) => _dragStart = d.localPosition;
  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStart == null || _engine.state != AppPhase.playing) return;
    final dx = d.localPosition.dx - _dragStart!.dx;
    final dy = d.localPosition.dy - _dragStart!.dy;
    if (dx.abs() > 28 && dx.abs() > dy.abs()) {
      dx > 0 ? _engine.moveRight() : _engine.moveLeft();
      _dragStart = null;
    } else if (dy.abs() > 28 && dy.abs() > dx.abs()) {
      dy < 0 ? _engine.moveForward() : _engine.moveBackward();
      _dragStart = null;
    }
  }

  Widget _buildAvatar({double size = 56}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.amber, width: 2),
        color: Colors.grey.shade800,
        boxShadow: [
          BoxShadow(
              color: Colors.amber.withValues(alpha: 0.3), blurRadius: 8)
        ],
      ),
      child: Icon(Icons.person,
          color: Colors.amber.shade300, size: size * 0.55),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: _loadError != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Failed to load game assets',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo.png', width: 120, height: 120),
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Loading...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF333333),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _engine.setSize(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            onTapUp: (_) => _handleTap(),
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: SceneRenderer(
                      engine: _engine,
                      assets: _assets,
                      activeSkin: _activeSkin),
                ),
                if (_engine.state == AppPhase.menu) _buildMenu(constraints),
                if (_engine.state == AppPhase.playing) _buildHUD(),
                if (_engine.state == AppPhase.paused) _buildPauseOverlay(),
                if (_engine.state == AppPhase.gameOver) ...[
                  _buildHUD(),
                  _buildGameOver(constraints),
                ],
                if (_showLeaderboard) _buildLeaderboardOverlay(),
                if (_showShop) _buildShopOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenu(BoxConstraints c) {
    final bob = sin(_engine.menuTime * 2.5) * 10;
    final chickenRotate = sin(_engine.menuTime * 1.8) * 0.08;
    final glowPulse = (sin(_engine.menuTime * 3) + 1) / 2;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildAvatar(size: 48),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _editName,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_playerName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Row(children: [
                          const Icon(Icons.monetization_on,
                              color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text('$_totalCoins',
                              style: TextStyle(
                                  color: Colors.amber.shade300, fontSize: 13)),
                        ]),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showShop = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('SKINS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showLeaderboard = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.leaderboard,
                          color: Colors.amber, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
            Image.asset('assets/game_name.png',
                width: c.maxWidth * 0.85, fit: BoxFit.contain),
            const SizedBox(height: 16),
            Transform.translate(
              offset: Offset(0, bob),
              child: Transform.rotate(
                angle: chickenRotate,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber
                            .withValues(alpha: 0.15 + glowPulse * 0.15),
                        blurRadius: 30 + glowPulse * 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    _skinAssetPath(_activeSkin),
                    width: _activeSkin == CharSkinType.classic ? 150 : 300,
                    height: _activeSkin == CharSkinType.classic ? 150 : 300,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const Spacer(flex: 1),
            _buildPlayButton(glowPulse),
            const SizedBox(height: 20),
            if (_engine.highScore > 0 || _engine.bestDistance > 0)
              _buildStatsBadge(),
            const Spacer(flex: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHintChip(Icons.swipe_up, 'TAP'),
                  const SizedBox(width: 12),
                  _buildHintChip(Icons.swipe_left, 'SWIPE'),
                  const SizedBox(width: 12),
                  _buildHintChip(Icons.speed, 'SURVIVE'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => WebPage(
                          title: 'Privacy Policy',
                          url: policyPageUrl,
                        ),
                      ));
                    },
                    child: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => WebPage(
                          title: 'Support',
                          url: helpPageUrl,
                        ),
                      ));
                    },
                    child: Text(
                      'Support',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showShop = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront, color: Colors.purple, size: 28),
                  SizedBox(width: 8),
                  Text('SKIN SHOP',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.monetization_on,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text('$_totalCoins',
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: allCharSkins.length,
                  itemBuilder: (ctx, i) {
                    final skin = allCharSkins[i];
                    final owned = _ownedSkins.contains(skin.type);
                    final active = _activeSkin == skin.type;
                    final canAfford = _totalCoins >= skin.price;

                    return GestureDetector(
                      onTap: () => _buySkin(skin.type),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(18),
                          border: active
                              ? Border.all(
                                  color: Colors.amber.withValues(alpha: 0.5),
                                  width: 2)
                              : Border.all(
                                  color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Image.asset(skin.asset,
                                  fit: BoxFit.contain),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(skin.name,
                                      style: TextStyle(
                                          color: active
                                              ? Colors.amber
                                              : Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  if (active)
                                    const Text('EQUIPPED',
                                        style: TextStyle(
                                            color: Colors.amber,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1))
                                  else if (owned)
                                    const Text('OWNED',
                                        style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1))
                                  else
                                    Row(children: [
                                      const Icon(Icons.monetization_on,
                                          color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text('${skin.price}',
                                          style: TextStyle(
                                              color: canAfford
                                                  ? Colors.amber
                                                  : Colors.red.shade300,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold)),
                                    ]),
                                ],
                              ),
                            ),
                            if (active)
                              const Icon(Icons.check_circle,
                                  color: Colors.amber, size: 28)
                            else if (owned)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text('EQUIP',
                                    style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: canAfford
                                      ? const LinearGradient(colors: [
                                          Color(0xFFFFC107),
                                          Color(0xFFFF9800)
                                        ])
                                      : null,
                                  color: canAfford
                                      ? null
                                      : Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text('BUY',
                                    style: TextStyle(
                                        color: canAfford
                                            ? Colors.black
                                            : Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Tap anywhere to close',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardOverlay() {
    final allPlayers = <_BoardEntry>[];
    for (final f in _mockPlayers) {
      allPlayers
          .add(_BoardEntry(f.name, f.score, f.distance, f.color, null));
    }
    allPlayers.add(_BoardEntry(_playerName, _engine.highScore,
        _engine.bestDistance, Colors.amber, null));
    allPlayers.sort((a, b) => b.distance.compareTo(a.distance));
    final top = allPlayers.take(10).toList();

    return GestureDetector(
      onTap: () => setState(() => _showLeaderboard = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, color: Colors.amber, size: 28),
                  SizedBox(width: 8),
                  Text('LEADERBOARD (offline)',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sample scores — beat them!',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const SizedBox(width: 40),
                  const SizedBox(width: 46),
                  const Expanded(
                      child: Text('Player',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11))),
                  SizedBox(
                      width: 60,
                      child: Text('Dist',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.green.shade300, fontSize: 11))),
                  const SizedBox(
                      width: 60,
                      child: Text('Score',
                          textAlign: TextAlign.right,
                          style:
                              TextStyle(color: Colors.white38, fontSize: 11))),
                ]),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: top.length,
                  itemBuilder: (ctx, i) {
                    final e = top[i];
                    final isMe = e.name == _playerName;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.amber.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: isMe
                            ? Border.all(
                                color: Colors.amber.withValues(alpha: 0.4))
                            : null,
                      ),
                      child: Row(children: [
                        SizedBox(
                            width: 30,
                            child: Text('#${i + 1}',
                                style: TextStyle(
                                    color:
                                        i < 3 ? Colors.amber : Colors.white60,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold))),
                        const SizedBox(width: 6),
                        _boardAvatar(e, 36),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(e.name,
                                style: TextStyle(
                                    color: isMe ? Colors.amber : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600))),
                        SizedBox(
                            width: 60,
                            child: Text('${e.distance}m',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.green.shade300,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold))),
                        SizedBox(
                            width: 60,
                            child: Text('${e.score}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold))),
                      ]),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Tap anywhere to close',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardAvatar(_BoardEntry e, double size) {
    if (e.avatarBytes != null) {
      return ClipOval(
          child: Image.memory(e.avatarBytes!,
              width: size, height: size, fit: BoxFit.cover));
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: e.color.withValues(alpha: 0.3),
      child: Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
          style: TextStyle(
              color: e.color,
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildPlayButton(double glowPulse) {
    final scale = 1.0 + sin(_engine.menuTime * 3) * 0.04;
    return Transform.scale(
      scale: scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF66BB6A), Color(0xFF43A047)]),
          borderRadius: BorderRadius.circular(40),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF4CAF50)
                    .withValues(alpha: 0.3 + glowPulse * 0.3),
                blurRadius: 20 + glowPulse * 10,
                offset: const Offset(0, 6)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text('PLAY',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  shadows: [
                    Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ])),
        ]),
      ),
    );
  }

  Widget _buildStatsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.amber.shade800.withValues(alpha: 0.6),
          Colors.orange.shade900.withValues(alpha: 0.4),
        ]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star, color: Colors.amber.shade200, size: 20),
        const SizedBox(width: 6),
        Text('${_engine.highScore}',
            style: TextStyle(
                color: Colors.amber.shade200,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 14),
        Icon(Icons.straighten, color: Colors.green.shade300, size: 20),
        const SizedBox(width: 4),
        Text('${_engine.bestDistance}m',
            style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildHintChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white60, size: 16),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildHUD() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hudPill(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text('${_engine.score}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ])),
            const SizedBox(height: 4),
            _hudPill(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.straighten, color: Colors.green.shade300, size: 16),
              const SizedBox(width: 4),
              Text('${_engine.distance}m',
                  style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ])),
            const SizedBox(height: 4),
            _hudPill(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
              const SizedBox(width: 4),
              Text('${_engine.collectedCoins}',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
            ])),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _hudPill(
                child: Text('${_engine.multiplier.toStringAsFixed(2)}x',
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 17,
                        fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            if (_engine.state == AppPhase.playing)
              GestureDetector(
                onTap: () => _engine.togglePause(),
                child: _hudPill(
                    child:
                        const Icon(Icons.pause, color: Colors.white, size: 20)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _hudPill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _buildPauseOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pause_circle_outline,
                color: Colors.white, size: 80),
            const SizedBox(height: 16),
            const Text('PAUSED',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4)),
            const SizedBox(height: 20),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: 6),
                Text('${_engine.score}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 14),
                Icon(Icons.straighten,
                    color: Colors.green.shade300, size: 18),
                const SizedBox(width: 4),
                Text('${_engine.distance}m',
                    style: TextStyle(
                        color: Colors.green.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 24),
            _buildPlayButton(0.5),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _engine.returnToMenu(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.home, color: Colors.white70, size: 22),
                  SizedBox(width: 8),
                  Text('MENU',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildGameOver(BoxConstraints c) {
    final show = _engine.deathTimer > 1.5;
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      child: IgnorePointer(
        ignoring: !show,
        child: Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Image.asset(_skinDeadAssetPath(_activeSkin),
                          width: _activeSkin == CharSkinType.classic ? 100 : 200,
                          height: _activeSkin == CharSkinType.classic ? 100 : 200),
                      const SizedBox(height: 10),
                      const Text('GAME OVER',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 10)
                              ])),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Row(children: [
                          Expanded(
                              child: _statCard(Icons.star, 'SCORE',
                                  '${_engine.score}', Colors.amber)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _statCard(
                                  Icons.straighten,
                                  'DISTANCE',
                                  '${_engine.distance}m',
                                  Colors.green.shade300)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Row(children: [
                          Expanded(
                              child: _statCard(
                                  Icons.monetization_on,
                                  'COINS',
                                  '${_engine.collectedCoins}',
                                  Colors.amber)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _statCard(
                                  Icons.speed,
                                  'x${_engine.multiplier.toStringAsFixed(2)}',
                                  '+${_engine.coinReward}',
                                  Colors.orange)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (_engine.score >= _engine.highScore &&
                          _engine.score > 0)
                        _recordBadge('NEW BEST SCORE!',
                            [Colors.amber.shade700, Colors.orange.shade700]),
                      if (_engine.distance >= _engine.bestDistance &&
                          _engine.distance > 0)
                        _recordBadge('NEW DISTANCE RECORD!',
                            [Colors.green.shade700, Colors.teal.shade700]),
                      const SizedBox(height: 16),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _actionButton('RETRY', Icons.replay,
                                const [Color(0xFF66BB6A), Color(0xFF43A047)],
                                () => _engine.startGame()),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _engine.returnToMenu(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 14),
                                decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.2))),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.home,
                                          color: Colors.white70, size: 22),
                                      SizedBox(width: 8),
                                      Text('MENU',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2)),
                                    ]),
                              ),
                            ),
                          ]),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _showLeaderboard = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color:
                                      Colors.amber.withValues(alpha: 0.3))),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.leaderboard,
                                    color: Colors.amber, size: 20),
                                SizedBox(width: 8),
                                Text('LEADERBOARD',
                                    style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                              ]),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordBadge(String text, List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      ),
    );
  }

  Widget _actionButton(
      String label, IconData icon, List<Color> colors, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(30),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
                color: colors[0].withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
        ]),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _BoardEntry {
  final String name;
  final int score;
  final int distance;
  final Color color;
  final Uint8List? avatarBytes;
  _BoardEntry(
      this.name, this.score, this.distance, this.color, this.avatarBytes);
}
