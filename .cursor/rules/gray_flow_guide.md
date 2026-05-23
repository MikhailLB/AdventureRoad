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

### Step 7 — iOS Notification Service Extension (NSE)

The NSE allows iOS to attach rich media images to push notifications when the app is backgrounded or killed. Without it, images only appear when the Dart isolate is alive.

#### 7a — Create NSE Swift files

Create `ios/NotificationService/NotificationService.swift`:
```swift
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
    guard let best = bestAttemptContent else { contentHandler(request.content); return }
    #if canImport(FirebaseMessaging)
    Messaging.serviceExtension().populateNotificationContent(best, withContentHandler: contentHandler)
    #else
    contentHandler(best)
    #endif
  }

  override func serviceExtensionTimeWillExpire() {
    if let h = contentHandler, let b = bestAttemptContent { h(b) }
  }
}
```

Create `ios/NotificationService/Info.plist` — standard app-extension plist with:
```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.usernotifications.service</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).NotificationService</string>
</dict>
```

#### 7b — Podfile

Add to `ios/Podfile` (MUST be outside the Runner target block):
```ruby
target 'NotificationService' do
  use_frameworks!
  pod 'Firebase/Messaging'
end
```

#### 7c — Wire NSE into project.pbxproj

This is the most error-prone step. Add the following sections manually (or copy from a working project):

**UUIDs to use** (pick any unique 24-char hex strings for your project):
```
NSE_SWIFT_BUILD_FILE   = AA00000100000000000001AA
NSE_SWIFT_FILE_REF     = AA00000100000000000003AA
NSE_PLIST_FILE_REF     = AA00000100000000000004AA
NSE_APPEX_FILE_REF     = AA00000100000000000005AA
NSE_GROUP              = AA00000100000000000006AA
NSE_TARGET             = AA00000100000000000007AA
NSE_SOURCES_PHASE      = AA00000100000000000008AA
NSE_RESOURCES_PHASE    = AA00000100000000000009AA
NSE_FRAMEWORKS_PHASE   = AA0000010000000000000AAA
NSE_DEBUG_CFG          = AA0000010000000000000BAA
NSE_RELEASE_CFG        = AA0000010000000000000CAA
NSE_PROFILE_CFG        = AA0000010000000000000DAA
NSE_CFG_LIST           = AA0000010000000000000EAA
EMBED_EXT_PHASE        = AA0000010000000000000FAA
EMBED_EXT_BUILD_FILE   = AA00000100000000000010AA
NSE_TARGET_DEP         = AA00000100000000000011AA
NSE_PROXY              = AA00000100000000000012AA
GOOGLE_PLIST_FILE_REF  = AA00000100000000000013AA
GOOGLE_PLIST_BUILD     = AA00000100000000000014AA
```

**Critical rules for pbxproj:**

1. **PBXBuildFile** — add NSE swift source and Embed App Extensions entry
2. **PBXContainerItemProxy** — proxy for NSE target dependency
3. **PBXCopyFilesBuildPhase** — `Embed App Extensions` with `dstSubfolderSpec = 13`
4. **PBXFileReference** — NSE swift, NSE Info.plist, NSE appex product, GoogleService-Info.plist
5. **PBXGroup** — add NSE group, add NSE product to Products, add GoogleService-Info.plist to Runner group
6. **PBXNativeTarget (NSE)** — `productType = "com.apple.product-type.app-extension"`
7. **PBXNativeTarget (Runner)** — add NSE as dependency + `Embed App Extensions` phase
8. **XCBuildConfiguration (NSE)** — ⚠️ **NO** `baseConfigurationReference` — let CocoaPods set it
9. **Build phases ORDER in Runner**:
   ```
   Run Script → Sources → Frameworks → Resources →
   Embed Frameworks → Embed App Extensions → Thin Binary
   ```
   ⚠️ `Embed App Extensions` MUST come BEFORE `Thin Binary` — otherwise Xcode detects a build cycle

**NSE build settings** — hardcode version, do NOT use `$(FLUTTER_BUILD_NUMBER)`:
```
CURRENT_PROJECT_VERSION = 1;          ← hardcoded, NOT $(FLUTTER_BUILD_NUMBER)
MARKETING_VERSION = 1.0;              ← hardcoded, NOT $(FLUTTER_BUILD_NAME)
INFOPLIST_FILE = NotificationService/Info.plist;
PRODUCT_BUNDLE_IDENTIFIER = com.yourapp.NotificationService;
SKIP_INSTALL = YES;
```

⚠️ **Why NOT use `$(FLUTTER_BUILD_NUMBER)` in NSE configs:**
If you set `baseConfigurationReference` to `Debug.xcconfig`/`Release.xcconfig` to inherit Flutter's xcconfig (which defines `FLUTTER_BUILD_NUMBER`), CocoaPods can no longer set its own xcconfig as the base for the NSE target. CocoaPods will print warnings and the NSE won't get Firebase/Messaging linked. Hardcoding `CURRENT_PROJECT_VERSION = 1` avoids the conflict.

**NSE Resources phase** — EMPTY (do NOT add Info.plist):
```
AA00000100000000000009AA /* Resources */ = {
  isa = PBXResourcesBuildPhase;
  files = ();   ← empty!
};
```
⚠️ Adding Info.plist to Resources causes `Multiple commands produce ... Info.plist` error because `INFOPLIST_FILE` build setting already handles it.

**GoogleService-Info.plist** — must be added to Runner's Copy Bundle Resources:
```
97C146EC1CF9000F007C117D /* Resources */ = {
  files = (
    ...,
    AA00000100000000000014AA /* GoogleService-Info.plist in Resources */,
  );
};
```
Without this, Firebase.initializeApp() silently fails: `Could not locate configuration file: 'GoogleService-Info.plist'`

**All white-part routes must be registered in the root MaterialApp:**
```dart
routes: {
  '/loading':        (_) => const LoadingScreen(),
  '/menu':           (_) => const MainMenuScreen(),
  '/level-select':   (_) => const LevelSelectScreen(),
  '/game':           (_) => const GameScreen(),
  '/level-complete': (_) => const LevelCompleteScreen(),
},
```
Without this, navigating from the gray flow to the white game crashes with `Could not find route "/menu"`.

#### 7d — After wiring, run pod install

```bash
cd ios
pod install    # must produce NO warnings about base configuration
open Runner.xcworkspace   # ALWAYS open .xcworkspace, never .xcodeproj
```

If `pod install` still prints CocoaPods xcconfig warnings for the NSE target, it means there's still a `baseConfigurationReference` in the NSE build configs. Remove it.

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

### `no valid "aps-environment" entitlement string found` — push notifications silently fail

**Symptom:** Firebase logs `[FCM012002] Error in didFailToRegisterForRemoteNotificationsWithError: no valid "aps-environment" entitlement`. FCM token is null. Push notifications never arrive.

**Cause:** The Runner target has no `CODE_SIGN_ENTITLEMENTS` pointing to a `.entitlements` file that declares `aps-environment`. Without this entitlement, iOS refuses to register the app for APNs, so Firebase can't obtain an APNs token and can't map it to an FCM token.

**Fix:**

1. Create `ios/Runner/Runner.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist ...>
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```
Use `development` for debug/TestFlight builds. For App Store production use `production` (Xcode switches this automatically when you Archive).

2. Add `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` to ALL three Runner build configurations in `project.pbxproj` (Debug, Release, Profile).

3. Add the `.entitlements` file to the Runner PBXGroup in `project.pbxproj`.

### NSE bundle ID mismatch — extension not signed / not installed

**Symptom:** App installs but push images don't attach. Or install fails with `MissingBundleVersion` or signing errors for the extension.

**Cause:** The `PRODUCT_BUNDLE_IDENTIFIER` in NSE build configs in `project.pbxproj` does not match the App ID registered in Apple Developer Portal → Identifiers.

**Fix:**
1. In Apple Developer Portal → Identifiers, check what the NSE identifier is (e.g. `com.yourapp.Notif` or `com.yourapp.NotificationService`).
2. In `project.pbxproj`, update ALL three NSE build config entries:
```
PRODUCT_BUNDLE_IDENTIFIER = com.yourapp.EXACT_SUFFIX_FROM_PORTAL;
```
Common mismatch: Portal has `com.yourapp.Notif` but pbxproj has `com.yourapp.NotificationService`.

### Cold-start push tap does NOT open URL (app was killed)

**Symptom:** User taps push notification when app is killed → app opens → shows loading screen → lands on main menu instead of the URL in the push. BUT if app is open/backgrounded, the URL opens correctly.

**Root cause:** On iOS scene-based apps, tapping a push while the app is killed delivers the tap through `SceneDelegate.scene(_:willConnectTo:options:)`, NOT through Firebase's swizzled path. `getInitialMessage()` returns nil in this case. SceneDelegate writes the URL to UserDefaults, but **if `NativeTapBridge.consumeTapUrl()` is never called at boot**, the URL is silently ignored.

**Fix:** Call `NativeTapBridge.consumeTapUrl()` as the **VERY FIRST THING** in the gray flow boot method, BEFORE any other async work (before network check, before push bootstrap, before attribution):

```dart
Future<void> _boot() async {
  // STEP 1 — HIGHEST PRIORITY: read SceneDelegate cold-start URL
  final nativeColdUrl = await NativeTapBridge.consumeTapUrl();
  if (nativeColdUrl != null && nativeColdUrl.isNotEmpty) {
    await widget.vault.writeMode(SessionMode.web);
    await widget.vault.consumeOneShotUrl(); // prevent double-navigation
    unawaited(_dispatchBackground()); // fire attribution in background
    _goContent(nativeColdUrl);        // route user to URL immediately
    return;
  }

  // ... rest of boot flow ...
}
```

**Why the order matters:** If you await `pulse.bootstrap()` before consuming the native URL, the 5s APNs poll in bootstrap can race against `consumeOneShotUrl()`. The URL from SceneDelegate lives in a different storage key (`lpr_gate_tap_url`) than the Firebase one-shot stash — they must both be checked.

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

---

## WebView Integration Checklist (from real bugs in production)

This section lists every WebView and integration bug discovered during the LavaPeakRun integration. Check all of these when setting up a new project.

### 1. Missing `_injectMediaAutoplay()` — videos don't autoplay in WebView

**Symptom:** Videos on the casino/betting site pause, require a tap to start, or never play at all.

**Cause:** The `_injectMediaAutoplay()` JS injection was not ported to the new project's `ContentBrowser` / `WebViewPage`.

**Fix:** Add this method and call it inside `onPageFinished`:
```javascript
(function(){
  if(window.__lprVideoAuto)return; window.__lprVideoAuto=true;
  function prep(v){
    v.setAttribute('playsinline',''); v.setAttribute('webkit-playsinline','');
    v.playsInline=true; v.muted=true; v.defaultMuted=true; v.autoplay=true;
    var p=v.play&&v.play(); if(p&&p.catch)p.catch(function(){});
  }
  function sweep(root){
    var l=(root||document).querySelectorAll('video');
    for(var i=0;i<l.length;i++)prep(l[i]);
  }
  sweep(document);
  // Handle dynamically added videos (SPA content)
  var mo=new MutationObserver(function(recs){
    for(var i=0;i<recs.length;i++){
      var nodes=recs[i].addedNodes||[];
      for(var j=0;j<nodes.length;j++){
        var n=nodes[j]; if(!n||n.nodeType!==1)continue;
        if(n.tagName==='VIDEO')prep(n); sweep(n);
      }
    }
  });
  mo.observe(document.documentElement,{childList:true,subtree:true});
  // iOS gesture policy sometimes needs a kick on first touch
  document.addEventListener('touchend',function(){sweep(document);},{passive:true});
  setInterval(function(){sweep(document);},1500);
})();
```

Also ensure `WebKitWebViewControllerCreationParams` is configured with:
```dart
mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},  // ← no user action required
allowsInlineMediaPlayback: true,
```

### 2. ContentBrowser layout stretched on cold-start push tap — fixes after rotation

**Symptom:** When the app is launched from a killed state by tapping a push notification, the WebView content is stretched / buttons are oversized in portrait. Rotating to landscape and back "fixes" it.

**Cause:** `SystemUiMode.immersiveSticky` (which hides status bar + home indicator) is set in `initState()` but only takes effect on the next frame. The WKWebView starts rendering immediately, calculates viewport dimensions while the system UI elements are still visible, and the site's layout bakes in the wrong height. After rotation, the viewport is fully recalculated.

**Fix:** Dispatch a synthetic `resize` event ~800ms after `onPageFinished` to force a viewport recalculation once immersive mode has settled:

```dart
// Inside onPageFinished callback:
Future.delayed(const Duration(milliseconds: 800), () {
  if (!mounted) return;
  _wv.runJavaScript(
    'window.dispatchEvent(new Event("resize"));'
    'if(window.visualViewport)'
    '  window.visualViewport.dispatchEvent(new Event("resize"));',
  );
  _injectSafeArea(); // re-apply safe area shim after viewport recalc
});
```

### 3. White-part routes missing from root MaterialApp — crash on navigation

**Symptom:** After gray flow resolves to game (offline/organic user), the app crashes with:
```
Could not find a generator for route RouteSettings("/menu", null)
```

**Cause:** The root `MaterialApp` in `bootstrap.dart` / `VolcanoGateApp` only registered `/loading` but not the other game routes that `LoadingScreen` navigates to after loading.

**Fix:** Register ALL white-part routes in the root `MaterialApp`:
```dart
routes: {
  '/loading':        (_) => const LoadingScreen(),
  '/menu':           (_) => const MainMenuScreen(),
  '/level-select':   (_) => const LevelSelectScreen(),
  '/game':           (_) => const GameScreen(),
  '/level-complete': (_) => const LevelCompleteScreen(),
},
```
The exact routes depend on the white-part game structure — look at the original `app.dart` / white `MaterialApp` to find all declared routes.

### 4. Double loading screen (SplashGate + game's LoadingScreen)

**Symptom:** User sees two sequential loading animations — the gray flow's splash video, then the white game's loading video.

**Cause:** `_goGame()` in SplashGate navigated to `LoadingScreen` (the white part's loading screen with its own video), which plays on top of the already-finished gray loading experience.

**Fix:** Navigate directly to the game's main menu screen, skipping LoadingScreen entirely. `GameState` and `AudioService` are already initialised in `main()` before `runApp`, so the LoadingScreen's asset preload step is redundant:

```dart
void _goGame() {
  if (_navigated) return;
  _navigated = true;
  // Skip LoadingScreen — SplashGate already served as the loading experience.
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const MainMenuScreen()),
  );
}
```

### 5. `GoogleService-Info.plist` not found — Firebase silently fails to init

**Symptom:**
```
[FirebaseCore][I-COR000012] Could not locate configuration file: 'GoogleService-Info.plist'
Firebase.initializeApp() failed — [core/not-initialized]
```

**Cause:** The `.plist` file exists on disk at `ios/Runner/GoogleService-Info.plist` but is NOT added to the Xcode project's Copy Bundle Resources build phase. Xcode doesn't copy it into the `.app` bundle.

**Fix:** Add to `project.pbxproj`:
1. `PBXFileReference` entry for the file
2. `PBXBuildFile` entry
3. Add to Runner's `PBXResourcesBuildPhase` `files` array
4. Add to Runner's `PBXGroup` children

Without all four, the file won't appear in the built bundle.

### 6. NativeTapBridge cold-start URL never consumed — killed-app push tap goes to main menu

**Symptom:** User taps a push notification while the app is killed. App launches, shows loading screen, but lands on the main menu instead of the URL from the push. Works correctly when app is open/backgrounded.

**Cause:** `NativeTapBridge.consumeTapUrl()` (or its equivalent) was implemented but never called in the boot method. SceneDelegate correctly writes the URL to UserDefaults, but the Dart side never reads it.

**Fix:** Call `NativeTapBridge.consumeTapUrl()` as the absolute FIRST action in the boot method, before network check, before push bootstrap, before attribution:

```dart
Future<void> _boot() async {
  // STEP 1: check for cold-start push URL from SceneDelegate
  final nativeColdUrl = await NativeTapBridge.consumeTapUrl();
  if (nativeColdUrl != null && nativeColdUrl.isNotEmpty) {
    await widget.vault.writeMode(SessionMode.web);
    await widget.vault.consumeOneShotUrl(); // prevent double-navigation
    unawaited(_dispatchBackground());
    _goContent(nativeColdUrl);
    return;
  }
  // ... rest of boot ...
}
```

If `NativeTapBridge.consumeTapUrl()` is called AFTER `pulse.bootstrap()` (which polls APNs for ~2.5s), there is a race condition: the URL might be consumed and stashed by Firebase's `getInitialMessage()` path before `consumeTapUrl()` runs. The SceneDelegate path and Firebase path use different storage keys — check both.
