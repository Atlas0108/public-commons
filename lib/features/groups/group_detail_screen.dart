import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import '../../widgets/close_to_shell.dart' show CloseToShellIconButton, popOrGoHome;

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

        final showOverflowMenu = isOwner || (isMember && !isOwner);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => popOrGoHome(context),
            ),
            title: const SizedBox.shrink(),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Copy link',
                onPressed: () => _copyGroupUrl(g.id),
              ),
              if (showOverflowMenu)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'manage':
                        _openEditGroupSheet(context, g);
                        break;
                      case 'invite':
                        _openInviteSheet(context, g);
                        break;
                      case 'leave':
                        _confirmLeave(context, g.id);
                        break;
                    }
                  },
                  itemBuilder: (ctx) {
                    final items = <PopupMenuEntry<String>>[];
                    if (isOwner) {
                      items.add(
                        const PopupMenuItem(
                          value: 'manage',
                          child: Text('Manage Group'),
                        ),
                      );
                      items.add(
                        const PopupMenuItem(
                          value: 'invite',
                          child: Text('Invite connections'),
                        ),
                      );
                    } else if (isMember) {
                      items.add(
                        const PopupMenuItem(
                          value: 'leave',
                          child: Text('Leave group'),
                        ),
                      );
                    }
                    return items;
                  },
                ),
            ],
          ),
          floatingActionButton: isMember
              ? FloatingActionButton.extended(
                  onPressed: () => _openPostToGroupSheet(context, g),
                  icon: const Icon(Icons.post_add_outlined),
                  label: const Text('Post'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _GroupProfileSummary(
                group: g,
                onRules: () => _openRulesSheet(context, g),
                onMembers: () => _openMembersSheet(context, g),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                    ),
                    const SizedBox(height: 12),
                    _GroupPostFeedSection(groupId: g.id),
                  ],
                ),
              ),
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

  String _buildGroupShareUrl(String groupId) {
    final path = '/groups/$groupId';
    if (kIsWeb) {
      return Uri.base.resolve(path).toString();
    }
    final raw = dotenv.env['APP_PUBLIC_URL']?.trim();
    if (raw != null && raw.isNotEmpty) {
      final base = raw.replaceAll(RegExp(r'/+$'), '');
      return '$base$path';
    }
    return 'https://publiccommons.app$path';
  }

  Future<void> _copyGroupUrl(String groupId) async {
    final url = _buildGroupShareUrl(groupId);
    await Clipboard.setData(ClipboardData(text: url));
    appScaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Group link copied to clipboard')),
    );
  }

  Future<void> _openRulesSheet(BuildContext context, CommonsGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rules', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (g.rules.trim().isEmpty)
                  Text(
                    'This group has not posted rules yet.',
                    style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                  )
                else
                  SelectableText(
                    g.rules,
                    style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(height: 1.45),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMembersSheet(BuildContext context, CommonsGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.52,
          minChildSize: 0.32,
          maxChildSize: 0.88,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(
                    'Members · ${g.memberIds.length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    itemCount: g.memberIds.length,
                    itemBuilder: (context, i) {
                      final uid = g.memberIds[i];
                      return _MemberRow(userId: uid, isOwner: uid == g.ownerId);
                    },
                  ),
                ),
              ],
            );
          },
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

  Future<void> _openEditGroupSheet(BuildContext context, CommonsGroup g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx);
        final height = MediaQuery.sizeOf(ctx).height;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: SizedBox(
            height: height,
            child: _EditGroupSheet(group: g),
          ),
        );
      },
    );
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

class _EditGroupSheet extends StatefulWidget {
  const _EditGroupSheet({required this.group});

  final CommonsGroup group;

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _rules;
  late GroupVisibility _visibility;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _name = TextEditingController(text: g.name);
    _description = TextEditingController(text: g.description);
    _rules = TextEditingController(text: g.rules);
    _visibility = g.visibility;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _rules.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<GroupService>().updateGroupDetails(
            groupId: widget.group.id,
            name: _name.text,
            description: _description.text,
            rules: _rules.text,
            visibility: _visibility,
          );
      if (!mounted) return;
      Navigator.pop(context);
      appScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Saved.')),
      );
    } on Object catch (e) {
      if (mounted) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        title: const Text('Edit group'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<GroupVisibility>(
            segments: const [
              ButtonSegment(
                value: GroupVisibility.public,
                label: Text('Public'),
                icon: Icon(Icons.public_outlined),
              ),
              ButtonSegment(
                value: GroupVisibility.private,
                label: Text('Private'),
                icon: Icon(Icons.lock_outline),
              ),
            ],
            selected: {_visibility},
            onSelectionChanged: _saving
                ? (_) {}
                : (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _visibility == GroupVisibility.public
                ? 'Anyone signed in can find this group and read its posts.'
                : 'Only members can read this group and its posts.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rules,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Rules',
              hintText: 'Community guidelines for members',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

class _GroupProfileSummary extends StatelessWidget {
  const _GroupProfileSummary({
    required this.group,
    required this.onRules,
    required this.onMembers,
  });

  final CommonsGroup group;
  final VoidCallback onRules;
  final VoidCallback onMembers;

  String _titleInitial() {
    final t = group.name.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final n = group.memberIds.length;
    final memberLine = n == 1 ? '1 member' : '$n members';
    final visibility = group.isPublic ? 'Public' : 'Private';

    final linkStyle = tt.labelLarge?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Text(
                  _titleInitial(),
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: tt.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$memberLine · $visibility',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (group.description.trim().isNotEmpty)
            Text(
              group.description.trim(),
              style: tt.bodyLarge?.copyWith(height: 1.45),
            )
          else
            Text(
              'No description yet.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: cs.primary,
                ),
                onPressed: onRules,
                child: Text('Rules', style: linkStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '|',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.outline,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: cs.primary,
                ),
                onPressed: onMembers,
                child: Text('Members', style: linkStyle),
              ),
            ],
          ),
        ],
      ),
    );
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
        final cs = Theme.of(context).colorScheme;
        if (posts.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Column(
                children: [
                  Icon(Icons.forum_outlined, size: 40, color: cs.outline),
                  const SizedBox(height: 12),
                  Text(
                    'No posts yet',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap Post to share an event, offer, request, or bulletin.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final p in posts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: cs.surfaceContainerLow,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (p.kind == PostKind.communityEvent) {
                        context.push('/event/${p.id}');
                      } else {
                        context.push('/posts/${p.id}');
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                p.kind == PostKind.communityEvent
                                    ? Icons.event_available_outlined
                                    : p.kind == PostKind.bulletin
                                        ? Icons.campaign_outlined
                                        : p.kind == PostKind.helpOffer
                                            ? Icons.handshake_outlined
                                            : Icons.support_agent_outlined,
                                color: cs.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.displayTitleLine,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${_kindLabel(p.kind)} · ${fmt.format(p.createdAt.toLocal())}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 2),
                            child: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
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
