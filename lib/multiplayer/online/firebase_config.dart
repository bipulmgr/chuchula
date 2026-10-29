import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase options are supplied at build time so no project credentials
/// live in the repository:
///
///     flutter build apk --dart-define-from-file=.env
///
/// See `.env.example` and docs/FIREBASE_SETUP.md. When the values are
/// missing, online play reports "not configured" and everything else works.
class FirebaseConfig {
  const FirebaseConfig._();

  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');

  /// Each platform is registered as its own app in the Firebase console,
  /// with its own app id. FIREBASE_APP_ID is the fallback for all of them.
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.bipulmgr.chuchula',
  );

  static String get appId {
    final specific = kIsWeb
        ? _webAppId
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => _androidAppId,
            TargetPlatform.iOS || TargetPlatform.macOS => _iosAppId,
            _ => _webAppId,
          };
    return specific.isNotEmpty ? specific : _appId;
  }

  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  /// Cloud Functions region (must match functions/src/index.ts).
  static const _functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
  );
  static String get functionsRegion =>
      _functionsRegion.isEmpty ? 'us-central1' : _functionsRegion;

  /// Use the local Firebase Emulator Suite (host:port base, e.g. 10.0.2.2).
  static const emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
    iosBundleId: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? iosBundleId
        : null,
  );
}
