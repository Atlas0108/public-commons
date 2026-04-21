import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/comment.dart';
import '../models/user_profile.dart';

class CommentsService {
  CommentsService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _uuid = const Uuid();

  final Map<String, String> _collectionCache = {};

  Future<String> _resolveCollection(String contentId) async {
    if (_collectionCache.containsKey(contentId)) {
      return _collectionCache[contentId]!;
    }
    final postSnap = await _firestore.collection('posts').doc(contentId).get();
    if (postSnap.exists) {
      _collectionCache[contentId] = 'posts';
      return 'posts';
    }
    _collectionCache[contentId] = 'events';
    return 'events';
  }

  CollectionReference<Map<String, dynamic>> _commentsRef(String collection, String contentId) =>
      _firestore.collection(collection).doc(contentId).collection('comments');

  Stream<List<PostComment>> commentsStream(String contentId) {
    return _firestore
        .collection('posts')
        .doc(contentId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .asyncExpand((postSnap) {
      if (postSnap.docs.isNotEmpty) {
        return Stream.value(
          postSnap.docs.map(PostComment.fromDoc).whereType<PostComment>().toList(),
        );
      }
      return _firestore
          .collection('events')
          .doc(contentId)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots()
          .map((snap) => snap.docs.map(PostComment.fromDoc).whereType<PostComment>().toList());
    });
  }

  Stream<int> commentCountStream(String contentId) {
    return commentsStream(contentId).map((comments) => comments.length);
  }

  Future<String> _authorDisplayName(User user) async {
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        final p = UserProfile.fromDoc(user.uid, data);
        final label = p.publicDisplayLabel.trim();
        if (label.isNotEmpty && label != 'Neighbor') return label;
      }
    } catch (_) {}
    return 'Neighbor';
  }

  Future<PostComment> addComment(String contentId, String text) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Comment cannot be empty');

    final collection = await _resolveCollection(contentId);
    final id = _uuid.v4();
    final authorName = await _authorDisplayName(user);

    final comment = PostComment(
      id: id,
      postId: contentId,
      authorId: user.uid,
      authorName: authorName,
      text: trimmed,
      createdAt: DateTime.now(),
    );

    await _commentsRef(collection, contentId).doc(id).set(comment.toMap());
    return comment;
  }

  Future<void> deleteComment(String contentId, String commentId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final collection = await _resolveCollection(contentId);
    final ref = _commentsRef(collection, contentId).doc(commentId);
    final snap = await ref.get();

    if (!snap.exists) return;

    final data = snap.data();
    if (data?['authorId'] != user.uid) {
      throw StateError('Only the author can delete this comment');
    }

    await ref.delete();
  }
}
