import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../app_trace.dart';

/// Uses [FirebaseApp.options.storageBucket] as an explicit `gs://` bucket so the
/// Storage SDK targets the same bucket as Firebase Console (e.g. `*.firebasestorage.app`).
FirebaseStorage createFirebaseStorage() {
  final raw = Firebase.app().options.storageBucket;
  if (raw == null || raw.isEmpty) {
    commonsTrace('createFirebaseStorage', 'no storageBucket, using default instance');
    return FirebaseStorage.instance;
  }
  final gs = raw.startsWith('gs://') ? raw : 'gs://$raw';
  commonsTrace('createFirebaseStorage', gs);
  return FirebaseStorage.instanceFor(bucket: gs);
}
