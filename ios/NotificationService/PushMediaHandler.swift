import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Notification Service Extension that allows iOS to display image attachments
/// in FCM pushes when the app is in background or killed.
///
/// Without this extension iOS ignores the image field from FCM payloads and
/// only shows the picture when the Dart isolate is alive and builds a local
/// notification in the foreground handler.
///
/// By calling Messaging.serviceExtension().populateNotificationContent we hand
/// off image decoding to FirebaseMessaging, which downloads and attaches the
/// image to the system-displayed notification automatically.
///
/// IMPORTANT: The backend APNs payload MUST include "mutable-content": 1 —
/// otherwise iOS will skip this extension entirely and ignore the image.
class PushMediaHandler: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var pendingContent: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    pendingContent = request.content.mutableCopy() as? UNMutableNotificationContent

    guard let pendingContent = pendingContent else {
      contentHandler(request.content)
      return
    }

    #if canImport(FirebaseMessaging)
    Messaging.serviceExtension().populateNotificationContent(
      pendingContent,
      withContentHandler: contentHandler
    )
    #else
    contentHandler(pendingContent)
    #endif
  }

  override func serviceExtensionTimeWillExpire() {
    if let contentHandler = contentHandler,
       let pendingContent = pendingContent {
      contentHandler(pendingContent)
    }
  }
}
