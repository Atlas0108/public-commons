import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_scaffold_messenger.dart' show appScaffoldMessengerKey;
import '../../core/models/group.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_connection.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/connection_service.dart';
import '../../core/services/group_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../widgets/close_to_shell.dart';

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final groupSvc = context.read<GroupService>();
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<CommonsGroup?>(
      stream: groupSvc.groupStream(groupId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Group'),
              actions: const [CloseToShellIconButton()],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Private group',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can’t view this group unless you’ve been added as a member.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Group'),
              actions: const [CloseToShellIconButton()],
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final g = snap.data;
        if (g == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Group'),
              actions: const [CloseToShellIconButton()],
            ),
            body: const Center(child: Text('Group not found.')),
          );
        }
        final isOwner = user?.uid == g.ownerId;
        final isMember = user != null && g.isMember(user.uid);

        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: const [CloseToShellIconButton()],
          ),
          floatingActionButton: isMember
              ? FloatingActionButton.extended(
                  onPressed: () => _openPostToGroupSheet(context, g),
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Post'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(
                    g.isPublic ? Icons.public : Icons.lock,
                    size: 18,
                  ),
                  label: Text(g.isPublic ? 'Public' : 'Private'),
                ),
              ),
              if (g.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(g.description, style: Theme.of(context).textTheme.bodyLarge),
              ],
              const SizedBox(height: 24),
              Text('Group posts', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _GroupPostFeedSection(groupId: g.id),
              const SizedBox(height: 28),
              Text('Members (${g.memberIds.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...g.memberIds.map((uid) => _MemberRow(userId: uid, isOwner: uid == g.ownerId)),
              if (isOwner) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _openInviteSheet(context, g),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Invite connections'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _editDetails(context, g),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit name & description'),
                ),
              ],
              if (isMember && !isOwner) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => _confirmLeave(context, g.id),
                  child: const Text('Leave group'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openPostToGroupSheet(BuildContext context, CommonsGroup g) {
    final gid = g.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: Icon(Icons.event_available_outlined, color: Theme.of(ctx).colorScheme.primary),
                  title: const Text('Event'),
                  subtitle: const Text('Calendar post for this group'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/post/new/event?groupId=$gid');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.handshake_outlined, color: Colors.green.shade700),
                  title: const Text('Offering help'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/compose?groupId=$gid&kind=offer');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.support_agent_outlined, color: Colors.blue.shade700),
                  title: const Text('Requesting help'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/compose?groupId=$gid&kind=request');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.campaign_outlined, color: Theme.of(ctx).colorScheme.tertiary),
                  title: const Text('Bulletin'),
                  subtitle: const Text('Text and optional photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/compose?groupId=$gid&kind=bulletin');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openInviteSheet(BuildContext context, CommonsGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _InviteConnectionsSheet(group: g),
        );
      },
    );
  }

  Future<void> _editDetails(BuildContext context, CommonsGroup g) async {
    final nameCtrl = TextEditingController(text: g.name);
    final descCtrl = TextEditingController(text: g.description);
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      try {
        await context.read<GroupService>().updateGroupDetails(
              groupId: g.id,
              name: nameCtrl.text,
              description: descCtrl.text,
            );
        if (context.mounted) {
          appScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Saved.')),
          );
        }
      } on Object catch (e) {
        if (context.mounted) {
          appScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Could not save: $e')),
          );
        }
      }
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _confirmLeave(BuildContext context, String id) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will need to be invited again to rejoin this private group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    try {
      await context.read<GroupService>().leaveGroup(id);
      if (context.mounted) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('You left the group.')),
        );
        context.go('/post');
      }
    } on Object catch (e) {
      if (context.mounted) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}

class _GroupPostFeedSection extends StatelessWidget {
  const _GroupPostFeedSection({required this.groupId});

  final String groupId;

  static String _kindLabel(PostKind k) {
    return switch (k) {
      PostKind.helpOffer => 'Offer',
      PostKind.helpRequest => 'Request',
      PostKind.communityEvent => 'Event',
      PostKind.bulletin => 'Bulletin',
    };
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd().add_jm();
    return StreamBuilder<List<CommonsPost>>(
      stream: context.read<PostService>().groupPostsFeed(groupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text(
            'Could not load posts.\n${snap.error}',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final posts = snap.data ?? [];
        if (posts.isEmpty) {
          return Text(
            'No posts yet. Tap Post to add an event, help post, or bulletin.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }
        return Column(
          children: [
            for (final p in posts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(
                      p.kind == PostKind.communityEvent
                          ? Icons.event_outlined
                          : p.kind == PostKind.bulletin
                              ? Icons.campaign_outlined
                              : p.kind == PostKind.helpOffer
                                  ? Icons.handshake_outlined
                                  : Icons.support_agent_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(p.displayTitleLine, maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_kindLabel(p.kind)} · ${fmt.format(p.createdAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (p.kind == PostKind.communityEvent) {
                        context.push('/event/${p.id}');
                      } else {
                        context.push('/posts/${p.id}');
                      }
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({required this.userId, required this.isOwner});

  final String userId;
  final bool isOwner;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final p = await context.read<UserProfileService>().fetchProfile(widget.userId);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _loading
        ? '…'
        : (_profile?.publicDisplayLabel.trim().isNotEmpty == true
            ? _profile!.publicDisplayLabel
            : 'Neighbor');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline),
      title: Text(label),
      subtitle: Text(
        widget.isOwner ? 'Owner' : 'Member',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: widget.userId != FirebaseAuth.instance.currentUser?.uid
          ? TextButton(
              onPressed: () => context.push('/u/${widget.userId}'),
              child: const Text('Profile'),
            )
          : null,
    );
  }
}

class _InviteConnectionsSheet extends StatelessWidget {
  const _InviteConnectionsSheet({required this.group});

  final CommonsGroup group;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Invite connections',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: StreamBuilder<List<UserConnection>>(
                stream: context.read<ConnectionService>().myConnectionsStream(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final peers = snap.data!.where((c) => !group.memberIds.contains(c.peerId)).toList();
                  if (peers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Everyone you’re connected with is already in this group.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: peers.length,
                    itemBuilder: (context, i) {
                      final c = peers[i];
                      return ListTile(
                        title: Text(c.peerDisplayName),
                        trailing: const Icon(Icons.person_add_alt_1_outlined),
                        onTap: () async {
                          try {
                            await context.read<GroupService>().addMembers(
                                  groupId: group.id,
                                  userIds: [c.peerId],
                                );
                            if (context.mounted) {
                              appScaffoldMessengerKey.currentState?.showSnackBar(
                                SnackBar(content: Text('Added ${c.peerDisplayName}.')),
                              );
                              Navigator.pop(context);
                            }
                          } on Object catch (e) {
                            if (context.mounted) {
                              appScaffoldMessengerKey.currentState?.showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
