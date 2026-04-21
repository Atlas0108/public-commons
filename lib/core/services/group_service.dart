import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group.dart';

class GroupService {
  GroupService(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');

  /// Groups the signed-in user belongs to, newest first (client-sorted).
  Stream<List<CommonsGroup>> myGroupsStream({int limit = 80}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return _groups
        .where('memberIds', arrayContains: uid)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(CommonsGroup.fromDoc).whereType<CommonsGroup>().toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<CommonsGroup?> groupStream(String groupId) {
    return _groups.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CommonsGroup.fromDoc(doc);
    });
  }

  /// Creates a group. [additionalMemberIds] must not include the current user (added automatically).
  Future<String> createGroup({
    required String name,
    required String description,
    required GroupVisibility visibility,
    List<String> additionalMemberIds = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final ref = _groups.doc();
    final memberIds = <String>{user.uid};
    for (final id in additionalMemberIds) {
      final t = id.trim();
      if (t.isNotEmpty && t != user.uid) memberIds.add(t);
    }
    await ref.set({
      'name': name.trim(),
      'description': description.trim(),
      'visibility': visibility == GroupVisibility.public ? 'public' : 'private',
      'ownerId': user.uid,
      'memberIds': memberIds.toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> addMembers({
    required String groupId,
    required List<String> userIds,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final trimmed = userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (trimmed.isEmpty) return;
    await _groups.doc(groupId).update({
      'memberIds': FieldValue.arrayUnion(trimmed),
    });
  }

  Future<void> leaveGroup(String groupId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final snap = await _groups.doc(groupId).get();
    final g = CommonsGroup.fromDoc(snap);
    if (g == null) throw StateError('Group not found');
    if (g.ownerId == user.uid) {
      throw StateError('Transfer ownership or delete the group before leaving.');
    }
    await _groups.doc(groupId).update({
      'memberIds': FieldValue.arrayRemove([user.uid]),
    });
  }

  Future<void> updateGroupDetails({
    required String groupId,
    required String name,
    required String description,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _groups.doc(groupId).update({
      'name': name.trim(),
      'description': description.trim(),
    });
  }
}
