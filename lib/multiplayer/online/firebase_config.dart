import 'package:firebase_core/firebase_core.dart';

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
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  /// Cloud Functions region (must match functions/src/index.ts).
  static const functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );

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
  );
}
