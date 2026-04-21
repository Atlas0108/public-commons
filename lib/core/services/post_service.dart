import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../app_trace.dart';
import '../geo/geo_utils.dart';
import '../models/user_profile.dart';
import '../models/post.dart';
import '../models/post_kind.dart';
import '../utils/cover_image_prepare.dart';

class PostService {
  PostService(this._firestore, this._auth, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  static const Duration _writeAckWait = Duration(seconds: 15);

  static const Duration _storagePutTimeout = Duration(seconds: 180);
  static const Duration _storageUrlTimeout = Duration(seconds: 45);

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection('posts');

  /// Newest posts first (for Home). Same ordering as [postsInRadius] but without geo filter.
  Stream<List<CommonsPost>> homePostsFeed({int limit = 50}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(CommonsPost.fromDoc)
              .whereType<CommonsPost>()
              .where((p) => !p.isGroupPost)
              .toList(),
        );
  }

  /// Posts for a group feed (`groupId` equals [groupId]), newest first.
  Stream<List<CommonsPost>> groupPostsFeed(String groupId, {int limit = 80}) {
    final gid = groupId.trim();
    if (gid.isEmpty) return Stream.value([]);
    return _posts
        .where('groupId', isEqualTo: gid)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(CommonsPost.fromDoc).whereType<CommonsPost>().toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Newest-first global list for admin moderation (same query as [homePostsFeed], higher cap).
  Stream<List<CommonsPost>> moderationPostsFeed({int limit = 500}) =>
      homePostsFeed(limit: limit);

  /// Current user’s posts, newest first (sorted client-side so no composite index is required).
  ///
  /// Tied to [FirebaseAuth.authStateChanges] so we resubscribe after auth restores; using
  /// [FirebaseAuth.currentUser] only once would yield [Stream.empty] and never update.
  Stream<List<CommonsPost>> myPostsFeed({int limit = 50}) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<List<CommonsPost>>.value([]);
      }
      return postsByAuthorId(user.uid, limit: limit);
    });
  }

  /// Posts by [authorId], newest first (client-sorted; no composite index).
  Stream<List<CommonsPost>> postsByAuthorId(String authorId, {int limit = 50}) {
    return _posts
        .where('authorId', isEqualTo: authorId)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(CommonsPost.fromDoc).whereType<CommonsPost>().toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<List<CommonsPost>> postsInRadius({
    required GeoPoint center,
    required double radiusMiles,
    int limit = 200,
  }) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = <CommonsPost>[];
      for (final doc in snap.docs) {
        final p = CommonsPost.fromDoc(doc);
        if (p == null || p.isGroupPost) continue;
        if (withinRadiusMiles(center, p.geoPoint, radiusMiles)) {
          list.add(p);
        }
      }
      return list;
    });
  }

  Future<String> _authorDisplayName(User user) async {
    final em = user.email?.trim();
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty && dn != em) return dn;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        final p = UserProfile.fromDoc(user.uid, data);
        final label = p.publicDisplayLabel.trim();
        if (label.isNotEmpty && label != 'Neighbor') return label;
      }
    } on Exception catch (e) {
      commonsTrace('PostService._authorDisplayName profile read', e);
    }
    return 'Neighbor';
  }

  Future<String> _awaitUploadTask(UploadTask task, Reference ref, String logLabel) async {
    try {
      await task.timeout(
        _storagePutTimeout,
        onTimeout: () async {
          try {
            await task.cancel();
          } on Object catch (_) {}
          throw TimeoutException(
            'Image upload timed out after ${_storagePutTimeout.inSeconds}s. '
            'Deploy rules to this bucket: firebase deploy --only storage. '
            'Set CORS: gsutil cors set storage-cors.json gs://public-commons.firebasestorage.app',
          );
        },
      );
    } on FirebaseException catch (e) {
      commonsTrace('PostService._awaitUploadTask FirebaseException', '${e.code} ${e.message}');
      rethrow;
    }
    commonsTrace('PostService._awaitUploadTask put complete', logLabel);
    return ref.getDownloadURL().timeout(
      _storageUrlTimeout,
      onTimeout: () => throw TimeoutException(
        'Got upload response but timed out fetching the download URL.',
      ),
    );
  }

  /// [webImageBlob] is a JS `Blob` from [blobFromObjectUrl] on web; avoids huge `Uint8List` → JS copies.
  Future<String> _uploadPostCoverImage({
    required String postId,
    Uint8List? bytes,
    Object? webImageBlob,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final mime = contentType.trim().isEmpty ? 'image/jpeg' : contentType.trim();

    if (webImageBlob != null) {
      commonsTrace('PostService._uploadPostCoverImage putBlob (web)', postId);
      final ext = mime.toLowerCase().contains('png') ? 'png' : 'jpg';
      final ref = _storage.ref('post_images/${user.uid}/$postId.$ext');
      final task = ref.putBlob(
        webImageBlob,
        SettableMetadata(contentType: mime),
      );
      return _awaitUploadTask(task, ref, postId);
    }

    if (bytes == null || bytes.isEmpty) {
      throw ArgumentError('image bytes or web blob required');
    }

    final prepared = await prepareCoverImageForUploadAsync(bytes, mime);
    commonsTrace(
      'PostService._uploadPostCoverImage prepared',
      '${prepared.bytes.length} bytes (was ${bytes.length})',
    );
    final ext = prepared.contentType.toLowerCase().contains('png') ? 'png' : 'jpg';
    final ref = _storage.ref('post_images/${user.uid}/$postId.$ext');
    final task = ref.putData(
      prepared.bytes,
      SettableMetadata(contentType: prepared.contentType),
    );
    return _awaitUploadTask(task, ref, postId);
  }

  Future<String> createPost({
    required PostKind kind,
    required String title,
    String? body,
    required GeoPoint geoPoint,
    Uint8List? imageBytes,
    String? imageContentType,
    Object? webImageBlob,
    /// When staff posts on behalf of an org (must be verified by caller).
    String? postAsAuthorUid,
    String? postAsAuthorName,
    /// When set, post appears only in that group’s feed (not global home/discovery).
    String? groupId,
  }) async {
    commonsTrace('PostService.createPost enter', title);
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final id = _uuid.v4();
    commonsTrace('PostService.createPost doc id', id);
    final orgUid = postAsAuthorUid?.trim();
    final orgName = postAsAuthorName?.trim();
    final useOrg =
        orgUid != null && orgUid.isNotEmpty && orgName != null && orgName.isNotEmpty;
    if (useOrg && (groupId != null && groupId.trim().isNotEmpty)) {
      throw StateError('Organization posts cannot be tied to a group.');
    }
    final authorId = useOrg ? orgUid : user.uid;
    final authorName = useOrg ? orgName : await _authorDisplayName(user);
    String? imageUrl;
    final mime = (imageContentType != null && imageContentType.trim().isNotEmpty)
        ? imageContentType.trim()
        : 'image/jpeg';
    final hasBlob = webImageBlob != null;
    final hasBytes = imageBytes != null && imageBytes.isNotEmpty;
    if (hasBlob || hasBytes) {
      commonsTrace(
        'PostService.createPost uploading image',
        hasBlob ? 'web Blob' : '${imageBytes?.length ?? 0} bytes',
      );
      imageUrl = await _uploadPostCoverImage(
        postId: id,
        bytes: hasBlob ? null : imageBytes,
        webImageBlob: hasBlob ? webImageBlob : null,
        contentType: mime,
      );
    }
    final gid = groupId?.trim();
    final post = CommonsPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      kind: kind,
      title: title,
      body: body,
      imageUrl: imageUrl,
      geoPoint: geoPoint,
      geohash: encodeGeohash(geoPoint.latitude, geoPoint.longitude),
      status: PostStatus.open,
      createdAt: DateTime.now(),
      groupId: gid != null && gid.isNotEmpty ? gid : null,
    );
    commonsTrace('PostService.createPost before posts/$id .set()');
    try {
      await _posts.doc(id).set(post.toCreateMap()).timeout(_writeAckWait);
      commonsTrace('PostService.createPost after .set() OK');
    } on TimeoutException {
      commonsTrace(
        'PostService.createPost .set() timed out',
        'continuing with $id — write may still complete in background',
      );
    }
    return id;
  }

  Future<void> updatePost({
    required CommonsPost post,
    required PostKind kind,
    required String title,
    String? body,
    required GeoPoint geoPoint,
    bool userRemovedCover = false,
    Uint8List? newCoverBytes,
    Object? newCoverWebBlob,
    String? newCoverContentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (post.authorId != user.uid) {
      throw StateError('Only the author can edit this post');
    }

    final hasNewCover =
        newCoverWebBlob != null || (newCoverBytes != null && newCoverBytes.isNotEmpty);

    final data = <String, dynamic>{
      'kind': postKindToFirestore(kind),
      'title': title.trim(),
      'tags': FieldValue.delete(),
      'geoPoint': geoPoint,
      'geohash': encodeGeohash(geoPoint.latitude, geoPoint.longitude),
    };

    final bodyTrim = body?.trim();
    if (bodyTrim != null && bodyTrim.isNotEmpty) {
      data['body'] = bodyTrim;
    } else {
      data['body'] = FieldValue.delete();
    }

    if (hasNewCover) {
      await _tryDeletePostCoverInStorage(post, user.uid);
      final mime = (newCoverContentType != null && newCoverContentType.trim().isNotEmpty)
          ? newCoverContentType.trim()
          : 'image/jpeg';
      final url = await _uploadPostCoverImage(
        postId: post.id,
        bytes: newCoverWebBlob != null ? null : newCoverBytes,
        webImageBlob: newCoverWebBlob,
        contentType: mime,
      );
      data['imageUrl'] = url;
    } else if (userRemovedCover) {
      await _tryDeletePostCoverInStorage(post, user.uid);
      data['imageUrl'] = FieldValue.delete();
    }

    await _posts.doc(post.id).update(data).timeout(_writeAckWait);
  }

  /// Removes the post document and, when possible, its cover image in Storage.
  Future<void> deletePost(CommonsPost post) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    if (post.authorId != user.uid) {
      throw StateError('Only the author can delete this post');
    }

    await _tryDeletePostCoverInStorage(post, user.uid);
    await _posts.doc(post.id).delete().timeout(_writeAckWait);
  }

  Future<void> _tryDeletePostCoverInStorage(CommonsPost post, String uid) async {
    final url = post.imageUrl?.trim();
    if (url == null || url.isEmpty) return;
    try {
      await _storage.refFromURL(url).delete();
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        commonsTrace('PostService.deletePost storage refFromURL', '${e.code} ${e.message}');
      }
    } catch (e) {
      commonsTrace('PostService.deletePost storage refFromURL', e);
    }
    for (final ext in ['jpg', 'png']) {
      try {
        await _storage.ref('post_images/$uid/${post.id}.$ext').delete();
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') {
          commonsTrace('PostService.deletePost storage path', '${e.code} ${e.message}');
        }
      }
    }
  }
}
