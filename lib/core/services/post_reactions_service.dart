import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/post_reaction.dart';

class ReactionCounts {
  const ReactionCounts({this.likes = 0, this.dislikes = 0});

  final int likes;
  final int dislikes;

  int get score => likes - dislikes;
}

class PostReactionsService {
  PostReactionsService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

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

  CollectionReference<Map<String, dynamic>> _reactionsRefSync(String collection, String contentId) =>
      _firestore.collection(collection).doc(contentId).collection('reactions');

  CollectionReference<Map<String, dynamic>> _postsReactionsRef(String postId) =>
      _firestore.collection('posts').doc(postId).collection('reactions');

  CollectionReference<Map<String, dynamic>> _eventsReactionsRef(String eventId) =>
      _firestore.collection('events').doc(eventId).collection('reactions');

  Stream<ReactionType?> myReactionStream(String contentId) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        return Stream<ReactionType?>.value(null);
      }
      return _combinedReactionStream(contentId, user.uid);
    });
  }

  Stream<ReactionType?> _combinedReactionStream(String contentId, String userId) {
    return _postsReactionsRef(contentId).doc(userId).snapshots().asyncExpand((postSnap) {
      if (postSnap.exists) {
        final data = postSnap.data();
        if (data != null) {
          final typeStr = data['type'] as String?;
          return Stream.value(ReactionTypeExtension.fromFirestore(typeStr));
        }
      }
      return _eventsReactionsRef(contentId).doc(userId).snapshots().map((eventSnap) {
        if (!eventSnap.exists) return null;
        final data = eventSnap.data();
        if (data == null) return null;
        final typeStr = data['type'] as String?;
        return ReactionTypeExtension.fromFirestore(typeStr);
      });
    });
  }

  Stream<ReactionCounts> reactionCountsStream(String contentId) {
    return _postsReactionsRef(contentId).snapshots().asyncExpand((postSnap) {
      int postLikes = 0;
      int postDislikes = 0;
      for (final doc in postSnap.docs) {
        final data = doc.data();
        final typeStr = data['type'] as String?;
        if (typeStr == 'like') {
          postLikes++;
        } else if (typeStr == 'dislike') {
          postDislikes++;
        }
      }
      if (postLikes > 0 || postDislikes > 0) {
        return Stream.value(ReactionCounts(likes: postLikes, dislikes: postDislikes));
      }
      return _eventsReactionsRef(contentId).snapshots().map((eventSnap) {
        int likes = 0;
        int dislikes = 0;
        for (final doc in eventSnap.docs) {
          final data = doc.data();
          final typeStr = data['type'] as String?;
          if (typeStr == 'like') {
            likes++;
          } else if (typeStr == 'dislike') {
            dislikes++;
          }
        }
        return ReactionCounts(likes: likes, dislikes: dislikes);
      });
    });
  }

  Stream<Map<String, ReactionCounts>> multipleReactionCountsStream(List<String> postIds) {
    if (postIds.isEmpty) return Stream.value({});
    final streams = postIds.map((id) {
      return reactionCountsStream(id).map((counts) => MapEntry(id, counts));
    });
    return _combineStreams(streams.toList());
  }

  Stream<Map<String, ReactionCounts>> _combineStreams(
    List<Stream<MapEntry<String, ReactionCounts>>> streams,
  ) {
    if (streams.isEmpty) return Stream.value({});
    final results = <String, ReactionCounts>{};
    return Stream.multi((controller) {
      final subs = <dynamic>[];
      for (final stream in streams) {
        subs.add(stream.listen((entry) {
          results[entry.key] = entry.value;
          controller.add(Map.from(results));
        }));
      }
      controller.onCancel = () {
        for (final sub in subs) {
          (sub as dynamic).cancel();
        }
      };
    });
  }

  Stream<Map<String, ReactionType>> myReactionsStream(List<String> contentIds) {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(<String, ReactionType>{});
      if (contentIds.isEmpty) return Stream.value(<String, ReactionType>{});

      final streams = contentIds.map((contentId) {
        return myReactionStream(contentId).map((type) {
          return MapEntry(contentId, type);
        });
      });

      return _combineReactionStreams(streams.toList());
    });
  }

  Stream<Map<String, ReactionType>> _combineReactionStreams(
    List<Stream<MapEntry<String, ReactionType?>>> streams,
  ) {
    if (streams.isEmpty) return Stream.value({});
    final results = <String, ReactionType?>{};
    return Stream.multi((controller) {
      final subs = <dynamic>[];
      for (final stream in streams) {
        subs.add(stream.listen((entry) {
          results[entry.key] = entry.value;
          final filtered = <String, ReactionType>{};
          for (final e in results.entries) {
            if (e.value != null) filtered[e.key] = e.value!;
          }
          controller.add(filtered);
        }));
      }
      controller.onCancel = () {
        for (final sub in subs) {
          (sub as dynamic).cancel();
        }
      };
    });
  }

  Future<void> react(String contentId, ReactionType type) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final collection = await _resolveCollection(contentId);
    final ref = _reactionsRefSync(collection, contentId).doc(user.uid);
    final snap = await ref.get();

    if (snap.exists) {
      final data = snap.data();
      final currentType = ReactionTypeExtension.fromFirestore(data?['type'] as String?);
      if (currentType == type) {
        await ref.delete();
        return;
      }
    }

    final reaction = PostReaction(
      postId: contentId,
      userId: user.uid,
      type: type,
      createdAt: DateTime.now(),
    );
    await ref.set(reaction.toMap());
  }

  Future<void> removeReaction(String contentId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final collection = await _resolveCollection(contentId);
    await _reactionsRefSync(collection, contentId).doc(user.uid).delete();
  }

  Future<void> like(String contentId) => react(contentId, ReactionType.like);

  Future<void> dislike(String contentId) => react(contentId, ReactionType.dislike);
}
