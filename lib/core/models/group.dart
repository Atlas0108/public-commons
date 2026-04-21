import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupVisibility {
  public,
  private,
}

/// A neighborhood group at `groups/{id}`.
class CommonsGroup {
  const CommonsGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.visibility,
    required this.ownerId,
    required this.memberIds,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final GroupVisibility visibility;
  final String ownerId;
  final List<String> memberIds;
  final DateTime createdAt;

  bool get isPublic => visibility == GroupVisibility.public;

  bool isMember(String uid) => memberIds.contains(uid);

  static GroupVisibility? _parseVisibility(Object? raw) {
    final s = (raw as String?)?.trim().toLowerCase();
    return switch (s) {
      'public' => GroupVisibility.public,
      'private' => GroupVisibility.private,
      _ => null,
    };
  }

  static CommonsGroup? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final vis = _parseVisibility(data['visibility']);
    if (vis == null) return null;
    final owner = (data['ownerId'] as String?)?.trim();
    if (owner == null || owner.isEmpty) return null;
    final membersRaw = data['memberIds'];
    if (membersRaw is! List) return null;
    final memberIds = membersRaw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    if (memberIds.isEmpty) return null;
    final name = (data['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final description = (data['description'] as String?)?.trim() ?? '';
    return CommonsGroup(
      id: doc.id,
      name: name,
      description: description,
      visibility: vis,
      ownerId: owner,
      memberIds: memberIds,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
