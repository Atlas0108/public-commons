import 'package:cloud_firestore/cloud_firestore.dart';

import 'post_kind.dart';

enum PostStatus { open, fulfilled }

class CommonsPost {
  const CommonsPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.title,
    this.body,
    this.imageUrl,
    required this.geoPoint,
    required this.geohash,
    required this.status,
    this.fulfilledByUserId,
    required this.createdAt,
    this.startsAt,
    this.endsAt,
    this.locationDescription,
    this.groupId,
    this.hidden = false,
  });

  final String id;
  final String authorId;
  /// Denormalized for feed cards (no extra profile reads).
  final String authorName;
  final PostKind kind;
  final String title;
  final String? body;
  final String? imageUrl;
  final GeoPoint geoPoint;
  final String geohash;
  final PostStatus status;
  final String? fulfilledByUserId;
  final DateTime createdAt;
  /// Set when [kind] is [PostKind.communityEvent].
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? locationDescription;
  /// When set, this post belongs to a group feed (not shown on global home/discovery).
  final String? groupId;
  /// When true, the post is hidden from feeds (auto-moderated due to dislikes).
  final bool hidden;

  /// True when this post is scoped to a group (`posts` with `groupId`).
  bool get isGroupPost {
    final g = groupId?.trim();
    return g != null && g.isNotEmpty;
  }

  /// Card / list primary line. [PostKind.bulletin] uses [body] (or “Photo”) instead of [title].
  String get displayTitleLine {
    if (kind == PostKind.bulletin) {
      final b = body?.trim();
      if (b != null && b.isNotEmpty) {
        final first = b.split('\n').first.trim();
        if (first.isEmpty) return 'Bulletin';
        return first.length > 140 ? '${first.substring(0, 140)}…' : first;
      }
      final img = imageUrl?.trim();
      if (img != null && img.isNotEmpty) return 'Photo';
      return 'Bulletin';
    }
    final t = title.trim();
    return t.isEmpty ? 'Post' : t;
  }

  /// Creates a [CommonsPost] from a [CommunityEvent] for unified display.
  static CommonsPost fromEvent(dynamic event) {
    return CommonsPost(
      id: event.id as String,
      authorId: event.organizerId as String,
      authorName: (event.organizerName as String).trim().isNotEmpty
          ? (event.organizerName as String).trim()
          : 'Organizer',
      kind: PostKind.communityEvent,
      title: event.title as String,
      body: event.description as String?,
      imageUrl: event.imageUrl as String?,
      geoPoint: event.geoPoint as GeoPoint,
      geohash: event.geohash as String,
      status: PostStatus.open,
      createdAt: event.createdAt as DateTime,
      startsAt: event.startsAt as DateTime?,
      endsAt: event.endsAt as DateTime?,
      locationDescription: event.locationDescription as String?,
    );
  }

  static CommonsPost? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final kind = postKindFromFirestore(data['kind'] as String?);
    if (kind == null) return null;
    final gp = data['geoPoint'];
    if (gp is! GeoPoint) return null;
    final rawName = (data['authorName'] as String?)?.trim();
    final startsAt = (data['startsAt'] as Timestamp?)?.toDate();
    final endsAt = (data['endsAt'] as Timestamp?)?.toDate();
    final loc = (data['locationDescription'] as String?)?.trim();
    final gid = (data['groupId'] as String?)?.trim();
    final hidden = data['hidden'] as bool? ?? false;
    return CommonsPost(
      id: doc.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: rawName != null && rawName.isNotEmpty ? rawName : 'Neighbor',
      kind: kind,
      title: data['title'] as String? ?? '',
      body: data['body'] as String?,
      imageUrl: data['imageUrl'] as String?,
      geoPoint: gp,
      geohash: data['geohash'] as String? ?? '',
      status: (data['status'] as String?) == 'fulfilled' ? PostStatus.fulfilled : PostStatus.open,
      fulfilledByUserId: data['fulfilledByUserId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startsAt: startsAt,
      endsAt: endsAt,
      locationDescription: loc != null && loc.isNotEmpty ? loc : null,
      groupId: gid != null && gid.isNotEmpty ? gid : null,
      hidden: hidden,
    );
  }

  Map<String, dynamic> toCreateMap() {
    final base = <String, dynamic>{
      'authorId': authorId,
      'authorName': authorName,
      'kind': postKindToFirestore(kind),
      'title': title,
      if (body != null && body!.isNotEmpty) 'body': body,
      if (imageUrl != null && imageUrl!.trim().isNotEmpty) 'imageUrl': imageUrl!.trim(),
      'geoPoint': geoPoint,
      'geohash': geohash,
      'status': status == PostStatus.fulfilled ? 'fulfilled' : 'open',
      if (fulfilledByUserId != null) 'fulfilledByUserId': fulfilledByUserId,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
    if (kind == PostKind.communityEvent) {
      if (startsAt != null) {
        base['startsAt'] = Timestamp.fromDate(startsAt!);
      }
      if (endsAt != null) {
        base['endsAt'] = Timestamp.fromDate(endsAt!);
      }
      if (locationDescription != null && locationDescription!.trim().isNotEmpty) {
        base['locationDescription'] = locationDescription!.trim();
      }
    }
    final g = groupId?.trim();
    if (g != null && g.isNotEmpty) {
      base['groupId'] = g;
    }
    return base;
  }
}
