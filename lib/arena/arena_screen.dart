import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../config/game_endpoints.dart';
import 'scene_assets.dart';
import 'arena_engine.dart';
import 'arena_painter.dart';

// ── Neon color constants for UI ──
const _cyan   = Color(0xFF00E5FF);
const _violet = Color(0xFFAA00FF);
const _magenta= Color(0xFFFF6FFF);
const _darkBg = Color(0xFF0D0521);
const _cardBg = Color(0xFF1A1040);

class _BoardEntry {
  final String name;
  final int score;
  final int distance;
  final Color color;
  final Uint8List? avatarBytes;
  _BoardEntry(this.name, this.score, this.distance, this.color, this.avatarBytes);
}

final List<_BoardEntry> _mockBoard = [
  _BoardEntry('NeonDash',    847, 210, Colors.cyanAccent, null),
  _BoardEntry('VoidRunner',  723, 185, const Color(0xFFAA00FF), null),
  _BoardEntry('GlitchBot',   612, 162, Colors.tealAccent, null),
  _BoardEntry('PulseKing',   589, 150, const Color(0xFFFF6FFF), null),
  _BoardEntry('ShadowShift', 501, 130, Colors.blueAccent, null),
  _BoardEntry('ArenaAce',    478, 118, Colors.greenAccent, null),
  _BoardEntry('ChromeZero',  432, 105, Colors.cyanAccent, null),
  _BoardEntry('NullFrag',    391,  92, Colors.purpleAccent, null),
  _BoardEntry('BitFire',     345,  80, const Color(0xFFFFCC00), null),
  _BoardEntry('GridBreaker', 298,  70, Colors.redAccent, null),
];

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen>
    with SingleTickerProviderStateMixin {
  final ArenaEngine _engine = ArenaEngine();
  final SceneAssets _assets = SceneAssets();
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  String _playerName = 'You';
  int _totalCoins = 0;
  bool _showLeaderboard = false;
  bool _showShop = false;
  bool _coinsSaved = false;
  bool _assetsReady = false;
  String? _loadError;

  // Splash video
  VideoPlayerController? _splashCtrl;
  bool _splashVideoReady = false;

  HeroVariant _activeHero = HeroVariant.classic;
  Set<HeroVariant> _ownedHeroes = {HeroVariant.classic};

  @override
  void initState() {
    super.initState();
    // Lock portrait only — game breaks in landscape and on iPad landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _ticker = createTicker(_onTick);
    _initSplash();
    _loadData();
  }

  Future<void> _initSplash() async {
    // Use addPostFrameCallback so context is fully mounted (MediaQuery works)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        // Game is portrait-only so always use the vertical splash
        const asset = 'assets/splash_v.mp4';
        final ctrl = VideoPlayerController.asset(asset);
        await ctrl.initialize();
        ctrl.setLooping(true);
        ctrl.setVolume(0);
        ctrl.play();
        if (!mounted) { ctrl.dispose(); return; }
        setState(() { _splashCtrl = ctrl; _splashVideoReady = true; });
      } catch (_) {
        // Fall back to dark background if video fails
      }
    });
  }

  Future<void> _loadData() async {
    try {
      await _assets.loadAll();
      final prefs = await SharedPreferences.getInstance();
      _engine.highScore    = prefs.getInt('arena_high_score') ?? 0;
      _engine.bestDistance = prefs.getInt('arena_best_distance') ?? 0;
      _totalCoins          = prefs.getInt('arena_coins') ?? 0;
      _playerName          = prefs.getString('arena_player_name') ?? 'You';

      final heroName = prefs.getString('arena_active_hero') ?? 'classic';
      _activeHero = HeroVariant.values.firstWhere(
        (h) => h.name == heroName,
        orElse: () => HeroVariant.classic,
      );

      final ownedList = prefs.getStringList('arena_owned_heroes') ?? ['classic'];
      _ownedHeroes = ownedList
          .map((n) => HeroVariant.values.firstWhere(
                (h) => h.name == n,
                orElse: () => HeroVariant.classic,
              ))
          .toSet();
      _ownedHeroes.add(HeroVariant.classic);

      if (mounted) {
        _assetsReady = true;
        _ticker.start();
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('arena_high_score',    _engine.highScore);
    await prefs.setInt('arena_best_distance', _engine.bestDistance);
    await prefs.setInt('arena_coins',         _totalCoins);
    await prefs.setString('arena_player_name', _playerName);
    await prefs.setString('arena_active_hero', _activeHero.name);
    await prefs.setStringList(
        'arena_owned_heroes', _ownedHeroes.map((h) => h.name).toList());
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    _engine.update(dt.clamp(0.0, 0.05));

    if (_engine.state == ArenaState.gameOver && !_coinsSaved) {
      _totalCoins += _engine.coinReward;
      _coinsSaved = true;
      _saveData();
    }
    if (_engine.state == ArenaState.playing) {
      _coinsSaved = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _splashCtrl?.dispose();
    // Keep portrait-only on dispose — don't re-enable landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  String _heroAssetPath(HeroVariant h) =>
      allHeroes.firstWhere((i) => i.type == h).asset;

  String _heroDeadAssetPath(HeroVariant h) =>
      allHeroes.firstWhere((i) => i.type == h).deadAsset;

  void _buyHero(HeroVariant hero) {
    final info = allHeroes.firstWhere((i) => i.type == hero);
    if (_ownedHeroes.contains(hero)) {
      _activeHero = hero;
      _saveData();
      setState(() {});
      return;
    }
    if (_totalCoins >= info.price) {
      _totalCoins -= info.price;
      _ownedHeroes.add(hero);
      _activeHero = hero;
      _saveData();
      setState(() {});
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _playerName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: const Text('Player Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 15,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your alias',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _cyan.withValues(alpha: 0.5))),
            focusedBorder:
                const UnderlineInputBorder(borderSide: BorderSide(color: _cyan)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save', style: TextStyle(color: _cyan))),
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
    if (_engine.state == ArenaState.menu) {
      _engine.startGame();
    } else if (_engine.state == ArenaState.playing) {
      _engine.moveForward();
    } else if (_engine.state == ArenaState.paused) {
      _engine.togglePause();
    }
  }

  Offset? _dragStart;
  void _onPanStart(DragStartDetails d) => _dragStart = d.localPosition;
  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragStart == null || _engine.state != ArenaState.playing) return;
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
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _cyan, width: 2),
        color: _cardBg,
        boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.3), blurRadius: 8)],
      ),
      child: Icon(Icons.person, color: _cyan, size: size * 0.55),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      return Scaffold(
        backgroundColor: _darkBg,
        body: _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                    const SizedBox(height: 12),
                    const Text('Failed to load game assets',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_loadError!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // Splash video background
                  if (_splashVideoReady && _splashCtrl != null)
                    SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _splashCtrl!.value.size.width,
                          height: _splashCtrl!.value.size.height,
                          child: VideoPlayer(_splashCtrl!),
                        ),
                      ),
                    )
                  else
                    const ColoredBox(color: _darkBg),
                  // Loading bar at bottom
                  Positioned(
                    left: 0, right: 0, bottom: 48,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 180,
                          height: 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(_cyan),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Loading...', style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                          letterSpacing: 1.5,
                        )),
                      ],
                    ),
                  ),
                ],
              ),
      );
    }

    return Scaffold(
      backgroundColor: _darkBg,
      body: LayoutBuilder(builder: (context, constraints) {
        _engine.setSize(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (_) => _handleTap(),
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          behavior: HitTestBehavior.opaque,
          child: Stack(children: [
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: ArenaPainter(engine: _engine, assets: _assets, activeHero: _activeHero),
            ),
            if (_engine.state == ArenaState.menu) _buildMenu(constraints),
            if (_engine.state == ArenaState.playing) _buildHUD(),
            if (_engine.state == ArenaState.paused) _buildPauseOverlay(),
            if (_engine.state == ArenaState.gameOver) ...[_buildHUD(), _buildGameOver(constraints)],
            if (_showLeaderboard) _buildLeaderboardOverlay(),
            if (_showShop) _buildShopOverlay(),
          ]),
        );
      }),
    );
  }

  // ── MENU ──

  Widget _buildMenu(BoxConstraints c) {
    final bob = sin(_engine.menuTime * 2.5) * 10;
    final heroRotate = sin(_engine.menuTime * 1.8) * 0.08;
    final glowPulse = (sin(_engine.menuTime * 3) + 1) / 2;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 1.2,
          colors: [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.75)],
        ),
      ),
      child: SafeArea(child: Column(children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            GestureDetector(
              onTap: _editName,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                children: [
                  _buildAvatar(size: 48),
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: _cyan, shape: BoxShape.circle,
                        border: Border.all(color: _cardBg, width: 1.5),
                      ),
                      child: const Icon(Icons.edit, color: Colors.white, size: 9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _editName,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_playerName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(children: [
                    const Icon(Icons.toll, color: _magenta, size: 14),
                    const SizedBox(width: 4),
                    Text('$_totalCoins', style: const TextStyle(color: _magenta, fontSize: 13)),
                  ]),
                ]),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _showShop = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_violet, Color(0xFF6600CC)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: _violet.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.storefront, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('SKINS', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _showLeaderboard = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cyan.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.leaderboard, color: _cyan, size: 18),
              ),
            ),
          ]),
        ),
        const Spacer(flex: 2),
        Image.asset('assets/title_card.webp', width: c.maxWidth * 0.85, fit: BoxFit.contain),
        const SizedBox(height: 16),
        Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(
            angle: heroRotate,
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                BoxShadow(
                  color: _cyan.withValues(alpha: 0.15 + glowPulse * 0.2),
                  blurRadius: 30 + glowPulse * 20,
                  spreadRadius: 5,
                ),
              ]),
              child: Image.asset(
                _heroAssetPath(_activeHero),
                width: _activeHero == HeroVariant.classic ? 150 : 300,
                height: _activeHero == HeroVariant.classic ? 150 : 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const Spacer(flex: 1),
        _buildPlayButton(glowPulse),
        const SizedBox(height: 20),
        if (_engine.highScore > 0 || _engine.bestDistance > 0) _buildStatsBadge(),
        const Spacer(flex: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildHintChip(Icons.swipe_up, 'TAP'),
          const SizedBox(width: 12),
          _buildHintChip(Icons.swipe_left, 'SWIPE'),
          const SizedBox(width: 12),
          _buildHintChip(Icons.flash_on, 'COMBO'),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(privacyPolicyPageUrl), mode: LaunchMode.externalApplication),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text('Privacy Policy', style: TextStyle(inherit: false, color: Colors.white.withValues(alpha: 0.55), fontSize: 11, decoration: TextDecoration.underline, decorationColor: Colors.white.withValues(alpha: 0.3))),
            ),
          ),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(supportPageUrl), mode: LaunchMode.externalApplication),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text('Support', style: TextStyle(inherit: false, color: Colors.white.withValues(alpha: 0.55), fontSize: 11, decoration: TextDecoration.underline, decorationColor: Colors.white.withValues(alpha: 0.3))),
            ),
          ),
        ]),
      ])),
    );
  }

  // ── SHOP ──

  Widget _buildShopOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showShop = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(child: Column(children: [
          const SizedBox(height: 16),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.storefront, color: _violet, size: 28),
            SizedBox(width: 8),
            Text('CHROME SHOP', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.toll, color: _magenta, size: 18),
            const SizedBox(width: 4),
            Text('$_totalCoins', style: const TextStyle(color: _magenta, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allHeroes.length,
              itemBuilder: (ctx, i) {
                final hero = allHeroes[i];
                final owned = _ownedHeroes.contains(hero.type);
                final active = _activeHero == hero.type;
                final canAfford = _totalCoins >= hero.price;
                return GestureDetector(
                  onTap: () => _buyHero(hero.type),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? _cyan.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: active
                          ? Border.all(color: _cyan.withValues(alpha: 0.5), width: 2)
                          : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(14)),
                        child: Image.asset(hero.asset, fit: BoxFit.contain),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hero.name, style: TextStyle(color: active ? _cyan : Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        if (active)
                          const Text('EQUIPPED', style: TextStyle(color: _cyan, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))
                        else if (owned)
                          const Text('OWNED', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))
                        else
                          Row(children: [
                            const Icon(Icons.toll, color: _magenta, size: 16),
                            const SizedBox(width: 4),
                            Text('${hero.price}', style: TextStyle(color: canAfford ? _magenta : Colors.red.shade300, fontSize: 14, fontWeight: FontWeight.bold)),
                          ]),
                      ])),
                      if (active)
                        const Icon(Icons.check_circle, color: _cyan, size: 28)
                      else if (owned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: Colors.greenAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                          child: const Text('EQUIP', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: canAfford ? const LinearGradient(colors: [_violet, Color(0xFF6600CC)]) : null,
                            color: canAfford ? null : Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('BUY', style: TextStyle(color: canAfford ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                    ]),
                  ),
                );
              },
            ),
          ),
          Padding(padding: const EdgeInsets.all(16),
              child: Text('Tap anywhere to close', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13))),
        ])),
      ),
    );
  }

  // ── LEADERBOARD ──

  Widget _buildLeaderboardOverlay() {
    final allEntries = <_BoardEntry>[..._mockBoard];
    allEntries.add(_BoardEntry(_playerName, _engine.highScore, _engine.bestDistance, _cyan, null));
    allEntries.sort((a, b) => b.distance.compareTo(a.distance));
    final top = allEntries.take(10).toList();

    return GestureDetector(
      onTap: () => setState(() => _showLeaderboard = false),
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: SafeArea(child: Column(children: [
          const SizedBox(height: 16),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.emoji_events, color: _cyan, size: 28),
            SizedBox(width: 8),
            Text('ARENA BOARD', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ]),
          const SizedBox(height: 4),
          Text('Sample scores — beat them!', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: top.length,
              itemBuilder: (ctx, i) {
                final e = top[i];
                final isMe = e.name == _playerName;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? _cyan.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: isMe ? Border.all(color: _cyan.withValues(alpha: 0.4)) : null,
                  ),
                  child: Row(children: [
                    SizedBox(width: 30, child: Text('#${i + 1}', style: TextStyle(color: i < 3 ? _cyan : Colors.white60, fontSize: 16, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 6),
                    CircleAvatar(radius: 18, backgroundColor: e.color.withValues(alpha: 0.3),
                        child: Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?', style: TextStyle(color: e.color, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.name, style: TextStyle(color: isMe ? _cyan : Colors.white, fontSize: 15, fontWeight: FontWeight.w600))),
                    SizedBox(width: 60, child: Text('${e.distance}m', textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold))),
                    SizedBox(width: 60, child: Text('${e.score}', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold))),
                  ]),
                );
              },
            ),
          ),
          Padding(padding: const EdgeInsets.all(16),
              child: Text('Tap anywhere to close', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13))),
        ])),
      ),
    );
  }

  // ── SHARED WIDGETS ──

  Widget _buildPlayButton(double glowPulse) {
    final scale = 1.0 + sin(_engine.menuTime * 3) * 0.04;
    return Transform.scale(
      scale: scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF00B0D8), Color(0xFF007ACC)]),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: _cyan.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(color: _cyan.withValues(alpha: 0.3 + glowPulse * 0.3), blurRadius: 20 + glowPulse * 10, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text('RUN', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 4,
              shadows: [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))])),
        ]),
      ),
    );
  }

  Widget _buildStatsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_violet.withValues(alpha: 0.5), _cyan.withValues(alpha: 0.3)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cyan.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star, color: _cyan, size: 20),
        const SizedBox(width: 6),
        Text('${_engine.highScore}', style: const TextStyle(color: _cyan, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 14),
        const Icon(Icons.straighten, color: Colors.greenAccent, size: 20),
        const SizedBox(width: 4),
        Text('${_engine.bestDistance}m', style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildHintChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cyan.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _cyan.withValues(alpha: 0.7), size: 16),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: _cyan.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── HUD ──

  Widget _buildHUD() {
    final showCombo = _engine.comboActive && _engine.state == ArenaState.playing;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hudPill(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, color: _cyan, size: 18),
              const SizedBox(width: 4),
              Text('${_engine.score}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ])),
            const SizedBox(height: 4),
            _hudPill(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.straighten, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 4),
              Text('${_engine.distance}m', style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
            ])),
            const SizedBox(height: 4),
            _hudPill(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.toll, color: _magenta, size: 16),
              const SizedBox(width: 4),
              Text('${_engine.collectedCoins}', style: const TextStyle(color: _magenta, fontSize: 14, fontWeight: FontWeight.bold)),
            ])),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _hudPill(child: Text('${_engine.multiplier.toStringAsFixed(2)}x',
                style: const TextStyle(color: _cyan, fontSize: 17, fontWeight: FontWeight.bold))),
            if (showCombo) ...[
              const SizedBox(height: 4),
              _hudPill(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.flash_on, color: _magenta, size: 14),
                const SizedBox(width: 2),
                Text('COMBO x${_engine.coinStreak}', style: const TextStyle(color: _magenta, fontSize: 12, fontWeight: FontWeight.bold)),
              ])),
            ],
            const SizedBox(height: 4),
            if (_engine.state == ArenaState.playing)
              GestureDetector(
                onTap: () => _engine.togglePause(),
                child: _hudPill(child: const Icon(Icons.pause, color: Colors.white, size: 20)),
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
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cyan.withValues(alpha: 0.2)),
      ),
      child: child,
    );
  }

  // ── PAUSE ──

  Widget _buildPauseOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pause_circle_outline, color: _cyan, size: 80),
        const SizedBox(height: 16),
        const Text('PAUSED', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: _cardBg, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, color: _cyan, size: 20),
            const SizedBox(width: 6),
            Text('${_engine.score}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 14),
            const Icon(Icons.straighten, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 4),
            Text('${_engine.distance}m', style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 24),
        _buildPlayButton(0.5),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => _engine.returnToMenu(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.home, color: Colors.white70, size: 22),
              SizedBox(width: 8),
              Text('MENU', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ]),
          ),
        ),
      ]))),
    );
  }

  // ── GAME OVER ──

  Widget _buildGameOver(BoxConstraints c) {
    final show = _engine.deathTimer > 1.5;
    return AnimatedOpacity(
      opacity: show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      child: IgnorePointer(
        ignoring: !show,
        child: Container(
          color: Colors.black.withValues(alpha: 0.88),
          child: SafeArea(child: Center(child: SingleChildScrollView(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(height: 20),
              Image.asset(_heroDeadAssetPath(_activeHero),
                  width: _activeHero == HeroVariant.classic ? 100 : 200,
                  height: _activeHero == HeroVariant.classic ? 100 : 200),
              const SizedBox(height: 10),
              const Text('TERMINATED', style: TextStyle(color: _magenta, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 3,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)])),
              const SizedBox(height: 20),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Row(children: [
                Expanded(child: _statCard(Icons.star, 'SCORE', '${_engine.score}', _cyan)),
                const SizedBox(width: 10),
                Expanded(child: _statCard(Icons.straighten, 'DISTANCE', '${_engine.distance}m', Colors.greenAccent)),
              ])),
              const SizedBox(height: 10),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Row(children: [
                Expanded(child: _statCard(Icons.toll, 'CHIPS', '${_engine.collectedCoins}', _magenta)),
                const SizedBox(width: 10),
                Expanded(child: _statCard(Icons.speed, 'x${_engine.multiplier.toStringAsFixed(2)}', '+${_engine.coinReward}', _violet)),
              ])),
              const SizedBox(height: 12),
              if (_engine.score >= _engine.highScore && _engine.score > 0)
                _recordBadge('NEW BEST SCORE!', [_violet, _cyan]),
              if (_engine.distance >= _engine.bestDistance && _engine.distance > 0)
                _recordBadge('NEW DISTANCE RECORD!', [Colors.greenAccent.shade700, Colors.tealAccent.shade700]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _actionButton('RETRY', Icons.replay, [const Color(0xFF00B0D8), const Color(0xFF007ACC)], () => _engine.startGame()),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _engine.returnToMenu(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.home, color: Colors.white70, size: 22),
                      SizedBox(width: 8),
                      Text('MENU', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showLeaderboard = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(24), border: Border.all(color: _cyan.withValues(alpha: 0.3))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.leaderboard, color: _cyan, size: 20),
                    SizedBox(width: 8),
                    Text('ARENA BOARD', style: TextStyle(color: _cyan, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ))),
        ),
      ),
    );
  }

  Widget _recordBadge(String text, List<Color> colors) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
    ));
  }

  Widget _actionButton(String label, IconData icon, List<Color> colors, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
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
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
