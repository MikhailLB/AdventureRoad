# LavaPeakRun — Custom Screen Assets (HIGH PRIORITY)

## ⚠️ MANDATORY: Always use project-specific custom background assets

This project has custom-designed full-screen background images for two gray-flow
screens. **Never use generic Flutter widgets or video placeholders for these.**
Always locate and use the actual asset files from the project.

---

## Push Notification Permission Screen

**File:** `lib/screens/push_promo_screen.dart`

**Background assets (orientation-aware — BOTH must exist):**
- Portrait:  `assets/Notifications/Vertical_Notifications_Screen.webp`
- Landscape: `assets/Notifications/Horizontal_Notifications_Screen.webp`

**Implementation pattern:**
```dart
final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
final bgAsset = isLandscape
    ? 'assets/Notifications/Horizontal_Notifications_Screen.webp'
    : 'assets/Notifications/Vertical_Notifications_Screen.webp';

Image.asset(bgAsset, fit: BoxFit.cover, width: size.width, height: size.height)
```

Overlay the Accept/Skip buttons on top of this image as `Positioned` widgets.

---

## No Internet / No WiFi Screen

**File:** `lib/screens/no_internet_screen.dart`

**Background assets (orientation-aware — BOTH must exist):**
- Portrait:  `assets/Nowifi/Vertical_Nowifi_Screen.webp`
- Landscape: `assets/Nowifi/Horizontal_Nowifi_Screen.webp`

**Implementation pattern:**
```dart
final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
final bgAsset = isLandscape
    ? 'assets/Nowifi/Horizontal_Nowifi_Screen.webp'
    : 'assets/Nowifi/Vertical_Nowifi_Screen.webp';

Image.asset(bgAsset, fit: BoxFit.cover, width: size.width, height: size.height)
```

Overlay the Retry button as a `Positioned` widget at the bottom.

---

## No-Internet Detection in WebView (ContentScreen)

**File:** `lib/screens/content_screen.dart`

When connectivity drops, show `NoInternetScreen` **immediately** — do NOT wait
for a DNS probe. Use the connectivity stream directly:

```dart
_connSub = widget.connectivity.onConnectivityChanged.listen((results) {
  if (results.every((r) => r == ConnectivityResult.none)) {
    _showNoInternetImmediate(); // no async DNS check — fires instantly
  }
});
```

The `_showNoInternetImmediate()` method navigates without `await hasInternet()`.

---

## Landscape Safe Area (Camera Notch)

**File:** `lib/screens/content_screen.dart`

In landscape mode, apply `viewPadding.left` and `viewPadding.right` to the
WebView padding (for devices with camera notch on the side):

```dart
padding: isLandscape
    ? EdgeInsets.only(
        left:  MediaQuery.of(context).viewPadding.left,
        right: MediaQuery.of(context).viewPadding.right,
      )
    : EdgeInsets.only(top: MediaQuery.of(context).viewPadding.top),
```

---

## Notification Icon

**File:** `android/app/src/main/res/drawable/ic_notification.xml`

The push notification icon is a **flame/fire shape** — monochrome white on
transparent background. This matches the Lava Peak Run theme.

Requirements (Android):
- Format: Vector Drawable XML (`<vector>`)
- Color: `#FFFFFF` fill, transparent background
- Size: 24×24dp viewport
- Must NOT be the same as the launcher icon

**Do not replace with a bell, star, or generic icon.**
If the file is missing or needs to be regenerated, use this flame path:
```xml
<path
    android:fillColor="#FFFFFF"
    android:pathData="M17.66,11.2C17.43,10.9 17.15,10.64 16.89,10.38C16.22,9.78 15.46,9.35 14.82,8.72C13.33,7.26 13,4.85 13.95,3C13,3.23 12.17,3.75 11.46,4.32C8.87,6.4 7.85,10.07 9.07,13.22C9.11,13.32 9.15,13.42 9.15,13.55C9.15,13.77 9,13.97 8.8,14.05C8.57,14.15 8.33,14.09 8.14,13.93C8.08,13.88 8.04,13.83 8,13.76C6.87,12.33 6.69,10.28 7.45,8.64C5.78,10 4.87,12.3 5,14.47C5.06,14.97 5.12,15.47 5.3,15.97C5.45,16.57 5.73,17.17 6.08,17.7C7.08,19.23 8.86,20.36 10.7,20.55C12.65,20.74 14.72,20.36 16.19,19C17.81,17.5 18.39,15.12 17.66,11.2Z"/>
```

All assets are declared in `pubspec.yaml`. If you add new assets, register them:
```yaml
assets:
  - assets/Notifications/Vertical_Notifications_Screen.webp
  - assets/Notifications/Horizontal_Notifications_Screen.webp
  - assets/Nowifi/Vertical_Nowifi_Screen.webp
  - assets/Nowifi/Horizontal_Nowifi_Screen.webp
```
