# Gray Flow — Living Integration Guide
## For AI agents working on this project

---

## What Is This Project?

This is a Flutter app template that implements a **"gray flow"** — a dual-mode mobile app:

- **Gray mode (online):** Shows a WebView with URL provided by a remote backend. The app acts as a content shell.
- **White mode (offline):** Shows an offline game (fallback when the backend returns no URL).

The backend decides which users see the WebView based on attribution data (AppsFlyer install source, campaign, etc.). Organic/unattributed users typically get the game; users coming from specific ad campaigns get the WebView content.

**Why this architecture exists:** Allows one app binary to serve two completely different experiences, determined at runtime without code changes.

---

## Project Layout

```
lib/
├── main.dart               Entry point: Firebase, HttpAgent, services, runApp
├── bootstrap.dart          Root widget (StreetSurgeApp) — TODO: rename per project
├── cfg/                    ⚠️ ALL CREDENTIALS LIVE HERE
│   ├── app_config.dart     Bundle ID, App Store ID, app name
│   ├── network_cfg.dart    Encoded config endpoint URL
│   ├── tracker_data.dart   Encoded AppsFlyer key + Firebase project number
│   └── remote_paths.dart   Privacy policy + support URLs
├── pages/
│   ├── launch_page.dart    ★ CORE: splash video + routing logic
│   ├── notify_page.dart    Push permission promo screen (with video)
│   ├── web_view_page.dart  WebView + keyboard/safe-area JS injections
│   └── no_signal_page.dart No internet error screen with retry
├── infra/
│   ├── api_client.dart     POST to config endpoint, cache URL
│   ├── analytics_tracker.dart  AppsFlyer SDK init + attribution waiting
│   ├── cold_start_bridge.dart  iOS: read push URL written by SceneDelegate
│   ├── data_store.dart     SharedPreferences + SecureStorage wrapper
│   ├── http_agent.dart     HTTP client with real device User-Agent
│   ├── net_checker.dart    Internet connectivity check (DNS probe)
│   └── push_manager.dart   Firebase FCM + flutter_local_notifications
├── data/
│   ├── api_result.dart     API response model {ok, url, expires, message}
│   └── app_state.dart      online / offline / pending enum
├── helpers/
│   └── cipher.dart         ⚠️ XOR cipher — change seed per app
└── core/
    └── white_part.dart     ⚠️ TODO: replace with actual game widget

tool/
└── encode_keys.dart        Run with `dart run tool/encode_keys.dart` to encode secrets

ios/Runner/
├── SceneDelegate.swift     Captures push URLs on cold start
└── Info.plist              ⚠️ Multiple keys required — see iOS section below
```

---

## Setup Checklist (for a new project)

### Step 1 — Credentials in `lib/cfg/`

| File | What to change |
|------|---------------|
| `app_config.dart` | `iosAppStoreId`, `bundleId`, `appName` |
| `network_cfg.dart` | Byte arrays for config endpoint URL |
| `tracker_data.dart` | Byte arrays for AppsFlyer key, Firebase project number, GCD URL |
| `remote_paths.dart` | Privacy policy and support page URLs |
| `helpers/cipher.dart` | `seedBytes` — unique per app, drives all encoding |

### Step 2 — Encode secrets

```bash
dart run tool/encode_keys.dart
```

Fill in your values at the top of `tool/encode_keys.dart`, run it, copy the printed byte arrays into the cfg files.

**⚠️ Always use `dart run`, never PowerShell `foreach` loops for encoding.**
PowerShell truncates integers at 32 bits on Windows, producing wrong byte values.
Symptom: `FormatException: Invalid HTTP header field value` in network logs.

### Step 3 — Change cipher seed

Edit `seedBytes` in `lib/helpers/cipher.dart`. Use a short unique ASCII string (6–12 chars). Then re-encode all secrets (Step 2).

### Step 4 — Firebase config files

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

Both must match your bundle ID / applicationId exactly.
Add to `.gitignore` if the repo is public.

### Step 5 — Bundle IDs

| File | Field |
|------|-------|
| `android/app/build.gradle.kts` | `namespace` and `applicationId` |
| `ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER` (3 occurrences for Runner + 3 for RunnerTests) |
| `lib/cfg/app_config.dart` | `bundleId` constant |

Also: move `MainActivity.kt` to match the new package path.

### Step 6 — White part (your game)

Replace `WhitePartPlaceholder` in `lib/core/white_part.dart`:
1. Copy your game files into `lib/core/` (or subdirectory)
2. Replace `WhitePartPlaceholder` class with your game widget
3. Implement `MediaBundle.loadAll()` to preload assets

The single integration point is in `launch_page.dart`:
```dart
void _navigateToGame() {
  // ⚠️ TODO: Replace WhitePartPlaceholder with your game
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const WhitePartPlaceholder()),
  );
}
```

---

## Gray Flow Logic (launch_page.dart in detail)

```
AppState.pending (first launch)
  ├── No internet → NoSignalPage (retry → LaunchPage)
  └── Has internet
        ├── Init AppsFlyer, wait attribution (30s) + deepLink (12s)
        ├── POST to config endpoint with attribution body
        ├── Response ok + url → setAppMode(online) → WebView / NotifyPage
        └── Response error / no url → setAppMode(offline) → Game

AppState.online (returning user)
  ├── No internet → NoSignalPage
  ├── Push URL stored → WebView (from push tap)
  ├── Fresh API call → WebView (new URL)
  └── API fail + savedUrl → WebView (cached URL)

AppState.offline (returning user, flagged as white)
  ├── Has internet → tryRestoreOnlineContent()
  │     ├── API ok → setAppMode(online) → WebView (re-conversion)
  │     └── API fail → Game
  └── No internet → Game
```

**Key insight:** `AppState.offline` users can be "re-converted" to online on subsequent launches if the backend starts returning a URL for them. This is intentional.

---

## Obfuscation & Anti-Detection Practices

### 1. Encoded secrets (byte arrays)
- All sensitive strings (API URL, AppsFlyer key, Firebase project number) stored as XOR byte arrays
- The cipher key is derived from a seed via LCG — not a simple XOR
- **Never** hardcode URLs/keys as string literals
- Visible check: `grep -r "appsflyer\|firebase\|config\.php" lib/` should return nothing meaningful

### 2. Real device User-Agent
`http_agent.dart` builds a UA from actual device model/OS (via `device_info_plus`).
- Android: `Mozilla/5.0 (Linux; Android {sdk}; {brand} {model} Build/{build}) AppleWebKit/... Chrome/... Mobile Safari/...`
- iOS: `Mozilla/5.0 (iPhone; CPU iPhone OS {ver} like Mac OS X) AppleWebKit/... Safari/...`
- Fallback hardcoded UA used only if DeviceInfo throws
- Chrome/WebKit version fragments are also XOR-encoded in the binary

### 3. Generic class/variable names
Use names that don't reveal intent:
- `ApiClient` not `CasinoClient`
- `DataStore` not `GamblingStorage`
- `AnalyticsTracker` not `BettingTracker`
- `StreetSurgeApp` not `CasinoApp`

### 4. Firebase App Check
Prevents unauthorized calls to the config endpoint from patched APKs.
- Android: `playIntegrity` provider in release builds
- iOS: `deviceCheck` provider in release builds
- Debug builds use `debug` provider (requires no real device)

### 5. Secure storage
Content URLs are stored in `flutter_secure_storage` (AES-encrypted on Android, Keychain on iOS), not plain SharedPreferences.

### 6. Network security config (Android)
`android/app/src/main/res/xml/network_security_config.xml` — limits cleartext traffic and optionally adds trust anchors.

---

## iOS-Specific Notes

### Info.plist — Required Keys & Reviewer Justifications

```xml
<!-- Push notifications — background delivery -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
<!-- Reviewer note: "remote-notification" enables push delivery when app
     is backgrounded. "fetch" allows background content refresh. Both are
     standard for apps with personalized notification features. -->

<!-- Firebase swizzling — required for cold-start push handling -->
<key>FirebaseAppDelegateProxyEnabled</key>
<true/>
<!-- Reviewer note: Firebase requires this key to intercept APNs delegate
     methods for push notification routing. Without it, tapping a notification
     when the app is killed does not open the correct content. -->

<!-- AppsFlyer ATT — install attribution -->
<key>NSUserTrackingUsageDescription</key>
<string>Your data will be used to provide you with a better experience and personalized offers.</string>
<!-- Reviewer note: Used for install attribution via AppsFlyer SDK to measure
     campaign effectiveness. Follows Apple ATT guidelines. -->

<!-- WebView loads arbitrary web content -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoadsInWebContent</key>
    <true/>
</dict>
<!-- Reviewer note: NSAllowsArbitraryLoadsInWebContent only applies to
     WKWebView, NOT to URLSession. Required because some partner/affiliate
     web content may be served over HTTP. App networking itself uses HTTPS. -->

<!-- File upload in WebView -->
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to your photo library to upload files.</string>
<key>NSCameraUsageDescription</key>
<string>This app needs access to your camera to upload photos.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone for media playback.</string>
<!-- Reviewer note: All three are used exclusively for file upload within
     the embedded WebView (photo/document upload, video recording). -->
```

### ATT Dialog Timing
The ATT dialog MUST be shown after the first frame renders. iOS silently drops the request if `UIApplicationStateActive` is false.

```dart
// CORRECT — in analytics_tracker.dart
await WidgetsBinding.instance.endOfFrame;
await Future.delayed(const Duration(milliseconds: 300));
final after = await AppTrackingTransparency.requestTrackingAuthorization();

// WRONG — will fail silently on cold start
await AppTrackingTransparency.requestTrackingAuthorization(); // too early
```

### APNs Token Delay (CRITICAL)
`FirebaseMessaging.instance.getToken()` returns `null` on iOS if called before APNs has registered (typically 0.5–2.5 seconds after launch).

**Fix:** Poll before calling `getToken()`:
```dart
// push_manager.dart — _waitForApnsToken()
for (var attempt = 1; attempt <= 5; attempt++) {
  final apns = await messaging.getAPNSToken();
  if (apns != null && apns.isNotEmpty) return; // APNs ready
  await Future.delayed(const Duration(milliseconds: 500));
}
```

After user grants permission in `NotifyPage`, use `refreshTokenAfterConsent()` (14 retries × 700ms = up to 10s) because the delay is longer immediately after the user taps "Allow".

### Cold Start Push Tap (iOS)
When the app is **killed** and the user taps a push notification:
- Firebase's `onMessageOpenedApp` does NOT fire
- `getInitialMessage()` fires only if the app was already partially alive

**Fix implemented via SceneDelegate:**
1. `SceneDelegate.swift` reads the push URL from `launchOptions` or `userActivity`
2. Stores it in `UserDefaults` under key `flutter.ar_road_cold_start_url`
3. `ColdStartBridge.consumeLaunchUrl()` reads and deletes it on next Dart startup
4. `LaunchPage._run()` checks this BEFORE attribution flow and navigates directly

**⚠️ The key `ar_road_cold_start_url` in `ColdStartBridge` must match `SceneDelegate.launchUrlKey`.**
SharedPreferences on iOS adds a `flutter.` prefix automatically — the bridge accounts for this.

### SceneDelegate.swift
Must be present in `ios/Runner/`. Referenced in `Info.plist`:
```xml
<key>UISceneDelegateClassName</key>
<string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
```
Without SceneDelegate, cold-start push taps open the app but navigate to the main screen, not the notification URL.

---

## Android-Specific Notes

### Keyboard Handling in WebView

**Problem:** On Android, when the soft keyboard appears inside a WebView, form inputs can be hidden behind it.

**Solution — three-layer fix:**

**Layer 1 — AndroidManifest.xml:**
```xml
android:windowSoftInputMode="adjustResize"
```
Use `adjustResize`, NOT `adjustPan`. `adjustPan` shifts the whole window (including status bar), `adjustResize` correctly resizes the content area.

**Layer 2 — Flutter Scaffold:**
```dart
Scaffold(
  resizeToAvoidBottomInset: false, // ← critical for WebView
  body: WebViewWidget(controller: _controller),
)
```
`resizeToAvoidBottomInset: true` (default) makes Flutter try to resize the widget, conflicting with `adjustResize`.

**Layer 3 — JavaScript injection (web_view_page.dart `_injectKeyboardScrollFix`):**
```javascript
// Listens to visualViewport.resize (more reliable than window.onresize)
// and scrolls the focused input into view when keyboard appears.
window.visualViewport.addEventListener('resize', function() {
  if (vp.height < prev) { /* keyboard appeared */ scrollFocusedIntoView(); }
});
document.addEventListener('focusin', function(e) {
  setTimeout(scrollFocusedIntoView, 250); // slight delay for keyboard animation
});
```

### iOS WebView Auto-Zoom Fix
iOS auto-zooms when a focused `<input>` has `font-size < 16px`. This breaks the layout.

**Fix — CSS injection (web_view_page.dart `_injectAntiZoom`):**
```css
input, textarea, select { font-size: max(16px, 1em) !important; }
```
This ensures inputs are never smaller than 16px (iOS zoom threshold) without disabling user accessibility zoom.

---

### iOS Keyboard Jitter (inputs in WebView — клавиатура дёргается)

**Symptom:** The keyboard visibly jumps up/down when focusing an input inside WKWebView. Happens intermittently — sometimes after a few page loads, sometimes immediately. Reinstalling the app temporarily "fixes" it (different timing).

**Root cause — two independent triggers, both must be fixed:**

#### Trigger 1: `behavior:'smooth'` in `scrollIntoView` during keyboard animation

iOS keyboard animation takes ~250ms. The `scrollIntoView({ behavior:'smooth' })` call launches its own CSS-scroll animation simultaneously. Two `WKScrollView` animators run concurrently → iOS compositor fights itself → keyboard visibly jerks.

The problem compounds when the scroll is scheduled 3× at 250/500/800ms — each overlapping call restarts the conflict.

```javascript
// ❌ WRONG — causes jitter
el.scrollIntoView({ behavior: 'smooth', block: 'center' });
setTimeout(focusRoll, 250);
setTimeout(focusRoll, 500);
setTimeout(focusRoll, 800);

// ✅ CORRECT — instant scroll, single call after keyboard finishes animating
el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
setTimeout(focusRoll, 350); // single call, after ~250ms keyboard animation
```

#### Trigger 2: `setInterval(apply, 2500)` patching `meta[name="viewport"]` while keyboard is visible

The safe-area shim patches `viewport-fit=contain` into the viewport meta tag every 2.5s. Mutating the viewport meta while the keyboard is open forces WKWebView to recompute safe-area insets mid-animation → layout reflow → keyboard jumps.

This is why the bug appears "randomly" — it depends on whether the 2500ms interval fires while the keyboard is visible.

```javascript
// ❌ WRONG — patches viewport regardless of keyboard state
setInterval(apply, 2500);

// ✅ CORRECT — skip patch while keyboard is visible
function kbOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
}
function apply() {
    if (kbOpen()) return; // ← guard: never patch during keyboard
    // ... patch viewport meta and CSS ...
}
setInterval(apply, 2500); // guard is inside apply()
```

**Complete fixed implementation of both injections:**

```javascript
// _injectKeyboardScroll — fixed version
function focusRoll() {
    var el = document.activeElement;
    if (!inputLike(el)) return;
    var vp = window.visualViewport;
    if (vp) {
        var r = el.getBoundingClientRect();
        if (r.bottom > vp.offsetTop + vp.height - 20 || r.top < vp.offsetTop) {
            el.scrollIntoView({ behavior: 'auto', block: 'nearest' }); // ← instant
        }
    } else {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
}
document.addEventListener('focusin', function(e) {
    if (inputLike(e.target)) {
        setTimeout(focusRoll, 350); // ← single call after keyboard animation
    }
});
if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
        var h = window.visualViewport.height;
        if (h < prev) { setTimeout(focusRoll, 120); } // ← single call
        prev = h;
    });
}
```

```javascript
// _injectSafeAreaShim — fixed version (add kbOpen guard)
function kbOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
}
function apply() {
    if (kbOpen()) return; // ← critical guard
    // ... rest of apply() unchanged ...
}
// SPA route-change delays also slightly increased to avoid firing
// during keyboard-dismiss transition:
history[fn] = function() {
    var r = orig.apply(this, arguments);
    setTimeout(apply, 150); setTimeout(apply, 600); // was 80/400
    return r;
};
```

**Why "reinstall fixes it":** Fresh install resets page JS state (no service workers, no cached state that alters timing). The bug is deterministic but timing-dependent — on a fresh session the 2500ms interval doesn't happen to fire while a keyboard is animating. After a few sessions/navigations the timing aligns and the bug surfaces.

### Notification Channel (Android)
Must create the notification channel BEFORE showing any notifications:
```dart
await androidPlugin?.createNotificationChannel(
  const AndroidNotificationChannel(
    'high_importance_channel',          // ← must match AndroidManifest meta-data
    'High Importance Notifications',
    importance: Importance.high,
  ),
);
```
The channel ID `'high_importance_channel'` must match:
```xml
<!-- AndroidManifest.xml -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="high_importance_channel" />
```

### Foreground Notifications
- **Android:** Show via `flutter_local_notifications` (Firebase doesn't show banners when app is in foreground on Android)
- **iOS:** Call `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` — iOS system shows the banner. **Do NOT also show `flutter_local_notifications`** — it would duplicate the notification.

```dart
// push_manager.dart
void _handleForegroundMessage(RemoteMessage message) async {
  if (Platform.isIOS) return;  // iOS handles it via system presentation options
  // Android: show local notification...
}
```

---

## Common Errors & Fixes

### `FormatException: Invalid HTTP header field value`
**Cause:** Obfuscated User-Agent byte arrays decoded to garbage characters.
**Root cause:** Byte arrays were generated with PowerShell, which overflows 32-bit integers.
**Fix:** Use `dart run tool/encode_keys.dart` to regenerate. Never use PS for encoding.

### `FirebaseException: A request for permissions is already running`
**Cause:** `pushManager.requestPermission()` called concurrently (e.g., from NotifyPage while a previous call is still awaiting).
**Fix:** Add a boolean guard in `PushManager`:
```dart
bool _permissionRequesting = false;
Future<bool> requestPermission() async {
  if (_permissionRequesting) return false;
  _permissionRequesting = true;
  try {
    final settings = await _messaging!.requestPermission(...);
    // ...
  } finally {
    _permissionRequesting = false;
  }
}
```

### `FirebaseException: [core/duplicate-app]`
**Cause:** `Firebase.initializeApp()` called more than once (e.g., in a service constructor).
**Fix:** Call it ONLY in `main()`. Never call it in service `init()` methods.

### `getToken()` returns null on iOS
**Cause:** APNs hasn't registered yet.
**Fix:** Call `_waitForApnsToken()` before `getToken()`. See `push_manager.dart`.

### Keystore not found during Android build
**Cause:** `storeFile` path in `android/key.properties` is wrong.
**Fix:** Path is relative to `android/app/`. Example:
```properties
storeFile=upload-keystore.jks   # → android/app/upload-keystore.jks
```
NOT relative to `android/`. Verify: `android/app/` directory must contain the `.jks` file.

### WebView keyboard covers inputs (Android)
See "Keyboard Handling in WebView" section above. Three-layer fix required:
`adjustResize` in Manifest + `resizeToAvoidBottomInset: false` in Scaffold + JS `_injectKeyboardScrollFix`.

### iOS keyboard jitters / jumps when tapping inputs in WebView
**Symptom:** Keyboard visibly jumps up or down when focusing an email/password field. Intermittent — "sometimes after reinstall it goes away."
**Two independent root causes — both must be fixed:**
1. `scrollIntoView({ behavior:'smooth' })` conflicts with iOS keyboard animation → use `behavior:'auto'` + single `setTimeout(focusRoll, 350)` instead of 3× at 250/500/800ms.
2. `setInterval(apply, 2500)` inside `_injectSafeAreaShim` patches `meta[name="viewport"]` while keyboard is visible → add `kbOpen()` guard inside `apply()` that returns early when `visualViewport.height < innerHeight * 0.75`.

See **"iOS Keyboard Jitter"** section above for full code.

### Loading bar appears before video
**Cause:** `_videoReady` flag not checked before rendering the bar.
**Fix:** Gate bar rendering on `_videoReady`:
```dart
if (_videoReady)
  Positioned(/* ... loading bar ... */)
```

### `gradle clean` fails with AccessDeniedException
**Cause:** Gradle daemon is holding file locks.
**Fix:**
```powershell
cd android; .\gradlew.bat --stop; cd ..; flutter clean; flutter pub get
```

### `minSdk` too low
- `flutter_secure_storage` requires minSdk ≥ 18 (recommend 21+)
- `firebase_messaging` requires minSdk ≥ 21
- `coreLibraryDesugaring` needed for Java 8 APIs on older Android versions

---

## Merging Gray into White (Step-by-Step)

Starting from `ios-gray-template` branch:

```
1. git checkout -b my-new-app ios-gray-template

2. Fill credentials:
   - lib/cfg/app_config.dart     (iosAppStoreId, bundleId, appName)
   - lib/cfg/remote_paths.dart   (privacy policy + support URLs)
   - Edit tool/encode_keys.dart  (fill your URLs/keys)
   - dart run tool/encode_keys.dart
   - Paste output into lib/cfg/network_cfg.dart and tracker_data.dart

3. Change cipher seed in lib/helpers/cipher.dart, re-run encode_keys.dart

4. Add Firebase:
   - android/app/google-services.json
   - ios/Runner/GoogleService-Info.plist

5. Update bundle IDs:
   - android/app/build.gradle.kts (namespace + applicationId)
   - ios/Runner.xcodeproj/project.pbxproj (PRODUCT_BUNDLE_IDENTIFIER × 3)
   - Rename android/app/src/main/kotlin/ package directory
   - Update MainActivity.kt package declaration

6. Copy your game into lib/core/:
   - Replace WhitePartPlaceholder with your game widget
   - Implement MediaBundle.loadAll() for asset preloading

7. Update AndroidManifest.xml:
   - android:label (app name)
   - OneLink host (AppsFlyer → App Settings → OneLink)
   - Notification channel name (if changed)

8. Update ios/Runner/Info.plist:
   - CFBundleDisplayName + CFBundleName

9. flutter pub get && flutter analyze

10. Test on real device:
    - Attribution/push WILL NOT work on simulator
    - Use debugPrint logs in AnalyticsTracker to verify AppsFlyer init
    - Check [ApiClient] logs for config endpoint response
```

---

## pubspec.yaml Dependencies Reference

```yaml
dependencies:
  appsflyer_sdk: ^6.15.3          # Attribution tracking
  app_tracking_transparency: ^2.0.6+1  # iOS ATT dialog
  firebase_core: ^3.13.0          # Firebase init
  firebase_messaging: ^15.2.4     # Push notifications
  firebase_app_check: ^0.3.2+10   # Anti-abuse
  flutter_local_notifications: ^18.0.1  # Foreground push (Android)
  connectivity_plus: ^6.1.4       # Network state
  http: ^1.3.0                    # HTTP client
  device_info_plus: ^11.3.3       # Device UA building
  flutter_secure_storage: ^10.0.0 # Encrypted URL storage
  shared_preferences: ^2.5.3      # App state storage
  webview_flutter: ^4.13.1        # WebView
  webview_flutter_android: ^4.11.0
  webview_flutter_wkwebview: ^3.22.0
  video_player: ^2.9.3            # Loading screen video
  url_launcher: ^6.3.1            # Open external URLs
  file_picker: ^11.0.2            # WebView file upload
  package_info_plus: ^8.3.0       # App version info
```

---

## Backend API Contract

**Request** (POST to `AppConfig.apiEndpoint`):
```json
{
  "af_id": "appsflyer-uid",
  "af_status": "Non-organic",
  "media_source": "googleadwords_int",
  "campaign": "campaign_name",
  "is_first_launch": true,
  "bundle_id": "com.example.app",
  "os": "iOS",
  "store_id": "id1234567890",
  "locale": "en_US",
  "push_token": "fcm-or-apns-token",
  "firebase_project_id": "1234567890",
  "sub_id_10": "IDFA-if-ATT-granted"
}
```

**Response (show WebView):**
```json
{ "ok": true, "url": "https://content.example.com/...", "expires": 1234567890 }
```

**Response (show game):**
```json
{ "ok": false, "message": "organic" }
```

The `expires` field is a Unix timestamp. `DataStore.isUrlExpired()` checks it — expired URLs are still shown (content re-fetching happens on next launch).

---

## Git Branch Strategy

| Branch | Purpose |
|--------|---------|
| `ios-gray-template` | This template — clean gray flow, no credentials |
| `ios-gray-part` | Production gray flow for a specific app |
| `ios-white-part` | Game only (white part), no gray flow |
| `android-white-part` | Android game build |
| `android-gray-part` | Android gray flow build |

**Merge gray into white:**
```bash
git checkout ios-white-part
git merge ios-gray-template     # brings in gray flow code
# Resolve conflicts in pubspec.yaml, main.dart, AndroidManifest, Info.plist
# Then fill credentials and test
```

**Important:** When merging, `main.dart` from gray part MUST win (gray `main()` initializes Firebase etc.). The white part's game widget connects in `launch_page.dart → _navigateToGame()`.
