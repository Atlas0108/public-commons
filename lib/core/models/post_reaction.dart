import 'package:cloud_firestore/cloud_firestore.dart';

enum ReactionType { like, dislike }

class PostReaction {
  const PostReaction({
    required this.postId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  final String postId;
  final String userId;
  final ReactionType type;
  final DateTime createdAt;

  static PostReaction? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final typeStr = data['type'] as String?;
    if (typeStr == null) return null;
    final type = typeStr == 'like' ? ReactionType.like : ReactionType.dislike;
    return PostReaction(
      postId: data['postId'] as String? ?? '',
      userId: doc.id,
      type: type,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'type': type == ReactionType.like ? 'like' : 'dislike',
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }
}

extension ReactionTypeExtension on ReactionType {
  String toFirestore() => this == ReactionType.like ? 'like' : 'dislike';

  static ReactionType? fromFirestore(String? value) {
    if (value == 'like') return ReactionType.like;
    if (value == 'dislike') return ReactionType.dislike;
    return null;
  }
}
