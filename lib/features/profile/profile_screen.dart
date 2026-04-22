import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/auth_redirect.dart';
import '../../app/view_as_controller.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_account_type.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/group.dart';
import '../../core/services/group_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/connection_service.dart';
import '../../core/services/follow_service.dart';
import '../../core/services/messaging_service.dart';
import '../../core/services/user_profile_service.dart';
import '../inbox/chat_screen.dart';
import 'profile_connection_button.dart';
import 'set_home_area_sheet.dart';
import '../../core/utils/blob_from_object_url.dart';
// import '../../widgets/didit_verification_sheet.dart';
import '../../widgets/close_to_shell.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/interests_picker.dart';
import '../../widgets/pending_connection_requests_badge.dart';
import '../../widgets/post_feed_card.dart';
import '../../widgets/view_as_identity_menu.dart';

/// Matches the home cream canvas.
const _pageBackground = Color(0xFFF9F7F2);

const _headerGreen = Color(0xFF2E7D5A);
const _editFabGreen = Color(0xFF1F5C40);
const _slateSubtitle = Color(0xFF5B6B7A);
const _statBlue = Color(0xFF3D5A80);
// /// Verified badge on own profile (below location row).
// const _verifiedBlue = Color(0xFF2563EB);
const _gearBg = Color(0xFFECECEA);
const _gearIcon = Color(0xFF5C5C5C);
const _profileGearSize = 38.0;
const _profileGearIconSize = 16.0;

/// Home-area control in edit profile: show saved city/region label when set.
String _homeAreaEditButtonLabel(UserProfile p) {
  final city = p.homeCityLabel?.trim();
  if (p.homeGeoPoint == null) {
    return 'Set home for local feed';
  }
  if (city != null && city.isNotEmpty) {
    return city;
  }
  return 'Home area — tap to update';
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  /// When null, shows the signed-in user (e.g. Profile tab). When set, shows that member (e.g. from `/u/:userId`).
  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _selfEnsureRequested = false;

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _selfEnsureRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view your profile.')));
    }

    final viewAs = context.watch<ViewAsController>();
    final targetUid = widget.userId ?? viewAs.effectiveProfileUid;
    final svc = context.read<UserProfileService>();
    final fromShell = widget.userId == null;
    final fromProfileTab = fromShell;
    final actingAsOrganization = viewAs.isActingAsOrganization;

    Widget body = ColoredBox(
      color: _pageBackground,
      child: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: svc.profileStream(targetUid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = snap.data;
            if (p == null) {
              final loadingOwnAuthProfile = targetUid == user.uid;
              if (loadingOwnAuthProfile) {
                final email = user.email?.trim();
                if (email == null || email.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add an email address to your account to show your profile.',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: _slateSubtitle),
                      ),
                    ),
                  );
                }
                if (!_selfEnsureRequested) {
                  _selfEnsureRequested = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    unawaited(svc.ensureProfile(displayName: 'Neighbor'));
                  });
                }
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading your profile…'),
                    ],
                  ),
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'This neighbor’s profile is not available yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _slateSubtitle),
                  ),
                ),
              );
            }
            final isAuthUserDoc = user.uid == p.uid;
            return _ProfileBody(
              key: ValueKey(p.uid),
              profile: p,
              isAuthUserDoc: isAuthUserDoc,
              fromProfileTab: fromProfileTab,
              actingAsOrganization: actingAsOrganization,
            );
          },
        ),
      ),
    );

    if (fromShell) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [CloseToShellIconButton()],
      ),
      body: body,
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({
    super.key,
    required this.profile,
    required this.isAuthUserDoc,
    required this.fromProfileTab,
    required this.actingAsOrganization,
  });

  final UserProfile profile;
  final bool isAuthUserDoc;
  final bool fromProfileTab;
  final bool actingAsOrganization;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

/// Pins the profile name / View-as row + subtitle under the avatar while the rest scrolls.
class _ProfileIdentityPinnedDelegate extends SliverPersistentHeaderDelegate {
  _ProfileIdentityPinnedDelegate({
    required this.backgroundColor,
    required this.padding,
    required this.child,
    required this.showShadow,
  });

  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final Widget child;
  final bool showShadow;

  static const double _extent = 118;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: SizedBox(
        height: maxExtent,
        width: double.infinity,
        child: Padding(
          padding: padding,
          child: Align(
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileIdentityPinnedDelegate oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.padding != padding ||
        oldDelegate.child != child ||
        oldDelegate.showShadow != showShadow;
  }
}

enum _CommunitiesFilter { all, created, joined }

class _ProfileBodyState extends State<_ProfileBody> with SingleTickerProviderStateMixin {
  bool _uploadingPhoto = false;
  /// True once the user has scrolled past the avatar so the identity header is pinned.
  bool _identityHeaderStuck = false;
  late TabController _tabController;
  /// Filter for posts tab: null means all posts, otherwise filter by PostKind.
  PostKind? _postsFilter;
  /// Filter for communities tab.
  _CommunitiesFilter _communitiesFilter = _CommunitiesFilter.all;

  UserProfile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Matches [SliverPadding] top (20) + avatar (128) + gap before pinned header (20).
  static const double _identityStickScrollThreshold = 20 + 128 + 20;

  @override
  void didUpdateWidget(covariant _ProfileBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid) {
      _identityHeaderStuck = false;
    }
  }

  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProfileEditSheet(profile: profile),
    );
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    if (_uploadingPhoto) return;
    final profileService = context.read<UserProfileService>();
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;

    Uint8List? bytes;
    Object? webBlob;
    final mime = x.mimeType;

    if (kIsWeb) {
      webBlob = await blobFromObjectUrl(x.path);
      if (webBlob == null) {
        bytes = await x.readAsBytes();
      }
    } else {
      bytes = await x.readAsBytes();
    }

    if (!mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      await profileService.uploadAndSetProfilePhoto(
        imageBytes: bytes,
        webImageBlob: webBlob,
        imageContentType: mime,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update photo: $e')));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildPrimaryProfileActions(BuildContext context, ThemeData theme) {
    if (widget.isAuthUserDoc) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => _openChat(context),
        style: FilledButton.styleFrom(
          backgroundColor: _headerGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text('Message'),
      ),
    );
  }

  void _openChat(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final myUid = context.read<ViewAsController>().effectiveProfileUid;
    if (myUid.isEmpty) return;
    final id = MessagingService.conversationIdForPair(myUid, profile.uid);
    final otherName = UserProfile.displayNameForUi(
      profile.publicDisplayLabel,
      accountEmail: widget.isAuthUserDoc && !widget.actingAsOrganization ? me.email : null,
    );
    context.push(
      '/chat/$id',
      extra: ChatScreenRouteExtra(otherUserId: profile.uid, otherDisplayName: otherName),
    );
  }

  Widget _buildAvatarStack(String headerName) {
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Avatar(photoUrl: profile.photoUrl, name: headerName),
                      if (_uploadingPhoto)
                        ColoredBox(
                          color: Colors.black26,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.isAuthUserDoc && !widget.actingAsOrganization)
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: _editFabGreen,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _uploadingPhoto ? null : () => _pickAndUploadProfilePhoto(),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.add_a_photo,
                      color: _uploadingPhoto ? Colors.white54 : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, ThemeData theme) {
    switch (_tabController.index) {
      case 0:
        return _buildPostsTab(context, theme);
      case 1:
        return _buildGroupsTab(context, theme);
      case 2:
        return _buildConnectionsTab(context, theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPostsFilterChips(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PostFilterChip(
            label: 'All',
            selected: _postsFilter == null,
            onSelected: () => setState(() => _postsFilter = null),
          ),
          const SizedBox(width: 8),
          _PostFilterChip(
            label: 'Offers',
            selected: _postsFilter == PostKind.helpOffer,
            onSelected: () => setState(() => _postsFilter = PostKind.helpOffer),
          ),
          const SizedBox(width: 8),
          _PostFilterChip(
            label: 'Requests',
            selected: _postsFilter == PostKind.helpRequest,
            onSelected: () => setState(() => _postsFilter = PostKind.helpRequest),
          ),
          const SizedBox(width: 8),
          _PostFilterChip(
            label: 'Events',
            selected: _postsFilter == PostKind.communityEvent,
            onSelected: () => setState(() => _postsFilter = PostKind.communityEvent),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsTab(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPostsFilterChips(theme),
        const SizedBox(height: 16),
        StreamBuilder<List<CommonsPost>>(
          stream: context.read<PostService>().postsByAuthorId(profile.uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final allPosts = snap.data ?? [];
            final posts = _postsFilter == null
                ? allPosts
                : allPosts.where((p) => p.kind == _postsFilter).toList();
            if (allPosts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No posts yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                ),
              );
            }
            if (posts.isEmpty) {
              final filterLabel = _postsFilter == PostKind.helpOffer
                  ? 'offers'
                  : _postsFilter == PostKind.helpRequest
                      ? 'requests'
                      : 'events';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No $filterLabel yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < posts.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i < posts.length - 1 ? 16 : 0),
                    child: PostFeedCard(post: posts[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCommunitiesFilterChips(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _PostFilterChip(
            label: 'All',
            selected: _communitiesFilter == _CommunitiesFilter.all,
            onSelected: () => setState(() => _communitiesFilter = _CommunitiesFilter.all),
          ),
          const SizedBox(width: 8),
          _PostFilterChip(
            label: 'Created by you',
            selected: _communitiesFilter == _CommunitiesFilter.created,
            onSelected: () => setState(() => _communitiesFilter = _CommunitiesFilter.created),
          ),
          const SizedBox(width: 8),
          _PostFilterChip(
            label: 'Joined',
            selected: _communitiesFilter == _CommunitiesFilter.joined,
            onSelected: () => setState(() => _communitiesFilter = _CommunitiesFilter.joined),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsTab(BuildContext context, ThemeData theme) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommunitiesFilterChips(theme),
        const SizedBox(height: 16),
        StreamBuilder<List<CommonsGroup>>(
          stream: context.read<GroupService>().myGroupsStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final allGroups = snap.data ?? [];

            final createdGroups = currentUid != null
                ? allGroups.where((g) => g.ownerId == currentUid).toList()
                : <CommonsGroup>[];
            final joinedGroups = currentUid != null
                ? allGroups.where((g) => g.ownerId != currentUid).toList()
                : <CommonsGroup>[];

            final List<CommonsGroup> filteredGroups;
            switch (_communitiesFilter) {
              case _CommunitiesFilter.all:
                filteredGroups = allGroups;
              case _CommunitiesFilter.created:
                filteredGroups = createdGroups;
              case _CommunitiesFilter.joined:
                filteredGroups = joinedGroups;
            }

            if (allGroups.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Text(
                      'No communities yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                    ),
                    if (widget.isAuthUserDoc && !widget.actingAsOrganization) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => context.push('/groups/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('Create my first community'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _headerGreen,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/groups/manage'),
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Explore communities'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _headerGreen,
                          side: const BorderSide(color: _headerGreen),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }

            if (filteredGroups.isEmpty) {
              if (_communitiesFilter == _CommunitiesFilter.created) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        "You haven't created any communities yet.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.isAuthUserDoc && !widget.actingAsOrganization) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => context.push('/groups/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Create my first community'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _headerGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              } else if (_communitiesFilter == _CommunitiesFilter.joined) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        "You haven't joined any communities yet.",
                        style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.isAuthUserDoc && !widget.actingAsOrganization) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => context.push('/groups/manage'),
                          icon: const Icon(Icons.explore_outlined),
                          label: const Text('Explore communities'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _headerGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < filteredGroups.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i < filteredGroups.length - 1 ? 12 : 0),
                    child: _GroupListTile(group: filteredGroups[i]),
                  ),
                if (widget.isAuthUserDoc && !widget.actingAsOrganization) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.push('/groups/manage'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _headerGreen,
                      side: const BorderSide(color: _headerGreen),
                    ),
                    child: const Text('Manage communities'),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildConnectionsTab(BuildContext context, ThemeData theme) {
    final svc = context.read<ConnectionService>();
    final tappable = widget.isAuthUserDoc && !widget.actingAsOrganization;
    
    return StreamBuilder<int>(
      stream: svc.connectionCountStream(profile.uid),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$n',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: _headerGreen,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'CONNECTIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B6B6B),
                    ),
                  ),
                ],
              ),
            ),
            if (tappable) ...[
              const SizedBox(height: 16),
              StreamBuilder<int>(
                stream: svc.incomingRequestCountStream(),
                builder: (context, pendingSnap) {
                  final pending = pendingSnap.data ?? 0;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.push('/connections'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: pending > 0 
                                    ? const Color(0xFFFFEBEB)
                                    : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.person_add_outlined,
                                color: pending > 0 
                                    ? const Color(0xFFD32F2F)
                                    : _headerGreen,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connection Requests',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF141414),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    pending > 0
                                        ? '$pending pending ${pending == 1 ? 'request' : 'requests'}'
                                        : 'No pending requests',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _slateSubtitle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (pending > 0)
                              PendingConnectionRequestsBadge(count: pending),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right, color: _slateSubtitle, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push('/explore'),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.explore_outlined,
                            color: Color(0xFF1976D2),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Explore',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF141414),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Find neighbors to connect with',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _slateSubtitle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, color: _slateSubtitle, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = FirebaseAuth.instance.currentUser;
    final showOwnEmailHint = widget.isAuthUserDoc && !widget.actingAsOrganization;
    final headerName = UserProfile.displayNameForUi(
      profile.publicDisplayLabel,
      accountEmail: showOwnEmailHint ? me?.email : null,
    );
    final sinceYear = profile.createdAt?.year;
    final city = profile.homeCityLabel?.trim();
    final nb = profile.neighborhoodLabel?.trim();
    final primaryLocation = (city != null && city.isNotEmpty)
        ? city
        : (nb != null && nb.isNotEmpty)
        ? nb
        : 'Neighbor';
    final subtitle = [primaryLocation, if (sinceYear != null) 'Since $sinceYear'].join(' • ');

    final serif = GoogleFonts.playfairDisplay;

    final identityBlock = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer<ViewAsController>(
            builder: (context, viewAs, _) {
              if (widget.fromProfileTab && viewAs.staffOrganizations.isNotEmpty) {
                return const ViewAsIdentityMenu(
                  placement: ViewAsIdentityPlacement.profileBelowAvatar,
                );
              }
              return Text(
                headerName,
                textAlign: TextAlign.center,
                style: serif(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                  height: 1.15,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _slateSubtitle,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n.metrics.axis != Axis.vertical) return false;
            final px = n.metrics.pixels;
            final stuck = px >= _identityStickScrollThreshold;
            if (stuck != _identityHeaderStuck) {
              setState(() => _identityHeaderStuck = stuck);
            }
            return false;
          },
          child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Center(child: _buildAvatarStack(headerName)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const SizedBox(height: 20),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _ProfileIdentityPinnedDelegate(
              backgroundColor: _pageBackground,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              showShadow: _identityHeaderStuck,
              child: identityBlock,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    _LikesReceivedCard(userId: profile.uid),
                    const SizedBox(height: 12),
                    _FollowStatsCard(userId: profile.uid),
                    if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Bio',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _slateSubtitle,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        profile.bio!.trim(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                    if (profile.interests.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Interests',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _slateSubtitle,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: profile.interests.map((interest) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              interest,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _headerGreen,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _buildPrimaryProfileActions(context, theme),
                    const SizedBox(height: 12),
                    if (!widget.isAuthUserDoc && !(widget.fromProfileTab && widget.actingAsOrganization)) ...[
                      FollowButton(
                        targetUserId: profile.uid,
                        targetDisplayName: profile.publicDisplayLabel,
                        myDisplayName: me?.displayName ?? 'Neighbor',
                      ),
                      const SizedBox(height: 8),
                      ProfileConnectionButton(
                        otherUid: profile.uid,
                        otherDisplayName: profile.publicDisplayLabel,
                      ),
                    ],
                    if (widget.isAuthUserDoc &&
                        !widget.actingAsOrganization &&
                        (profile.accountType == UserAccountType.nonprofit ||
                            profile.accountType == UserAccountType.business)) ...[
                      const SizedBox(height: 16),
                      _StaffEntryCard(
                        onTap: () => context.push('/profile/staff'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: _headerGreen,
                        unselectedLabelColor: _slateSubtitle,
                        indicatorColor: _headerGreen,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        tabs: const [
                          Tab(text: 'Posts'),
                          Tab(text: 'Communities'),
                          Tab(text: 'Connections'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTabContent(context, theme),
                  ],
                ),
              ),
            ),
          ),
        ),
          ],
          ),
        ),
        if (widget.isAuthUserDoc && !widget.actingAsOrganization)
          Positioned(
            top: 8,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _profileGearSize,
                  height: _profileGearSize,
                  child: Material(
                    color: _gearBg,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.push('/saved'),
                      child: const Center(
                        child: Icon(
                          Icons.bookmark_outline,
                          color: _gearIcon,
                          size: _profileGearIconSize,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: _profileGearSize,
                  height: _profileGearSize,
                  child: Material(
                    color: _gearBg,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openEdit(context),
                      child: const Center(
                        child: Icon(
                          Icons.settings,
                          color: _gearIcon,
                          size: _profileGearIconSize,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PostFilterChip extends StatelessWidget {
  const _PostFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _headerGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _headerGreen : const Color(0xFFE0E0E0),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _headerGreen.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _slateSubtitle,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _GroupListTile extends StatelessWidget {
  const _GroupListTile({required this.group});

  final CommonsGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberCount = group.memberIds.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/groups/${group.id}'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.diversity_3_outlined,
                  color: _headerGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF141414),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$memberCount ${memberCount == 1 ? 'member' : 'members'}${group.isPublic ? '' : ' • Private'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _slateSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _slateSubtitle, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffEntryCard extends StatelessWidget {
  const _StaffEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.groups_outlined, color: _headerGreen, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STAFF',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _slateSubtitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invite teammates by email',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _slateSubtitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _Initials(name: name),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: Color(0xFFDDE8E0),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }
    return _Initials(name: name);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      final s = parts.first;
      initials = s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    } else {
      initials = '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return ColoredBox(
      color: const Color(0xFFDDE8E0),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.playfairDisplay(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: _headerGreen,
          ),
        ),
      ),
    );
  }
}

class _ProfileMetricCard extends StatelessWidget {
  const _ProfileMetricCard({required this.value, required this.label, required this.valueColor});

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B6B6B),
            ),
          ),
        ],
      ),
    );
  }
}

class _LikesReceivedCard extends StatelessWidget {
  const _LikesReceivedCard({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileService = context.read<UserProfileService>();

    return StreamBuilder<UserProfile?>(
      stream: profileService.profileStream(userId),
      builder: (context, snapshot) {
        final karma = snapshot.data?.karma ?? 0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE4EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Color(0xFFE91E63),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$karma',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE91E63),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'KARMA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B6B6B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionsMetricCard extends StatelessWidget {
  const _ConnectionsMetricCard({required this.userId, required this.tappable});

  final String userId;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ConnectionService>();
    return StreamBuilder<int>(
      stream: svc.connectionCountStream(userId),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        final card = Stack(
          clipBehavior: Clip.none,
          children: [
            _ProfileMetricCard(value: '$n', label: 'CONNECTIONS', valueColor: _headerGreen),
            if (tappable)
              Positioned(
                top: 10,
                right: 10,
                child: StreamBuilder<int>(
                  stream: svc.incomingRequestCountStream(),
                  builder: (context, pendingSnap) {
                    final pending = pendingSnap.data ?? 0;
                    if (pending <= 0) return const SizedBox.shrink();
                    return PendingConnectionRequestsBadge(count: pending);
                  },
                ),
              ),
          ],
        );
        if (!tappable) return card;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/connections'),
            child: card,
          ),
        );
      },
    );
  }
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _entityName;
  late final TextEditingController _bio;
  late List<String> _interests;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _firstName = TextEditingController(text: p.firstName ?? '');
    _lastName = TextEditingController(text: p.lastName ?? '');
    _entityName = TextEditingController(
      text: p.accountType == UserAccountType.nonprofit
          ? (p.organizationName ?? '')
          : p.accountType == UserAccountType.business
              ? (p.businessName ?? '')
              : '',
    );
    _bio = TextEditingController(text: p.bio ?? '');
    _interests = List.from(p.interests);
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _entityName.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _openSetHomeAreaWithProfile(UserProfile p) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SetHomeAreaSheet(profile: p),
    );
  }

  Future<void> _save() async {
    final p = widget.profile;
    final t = p.accountType;
    if (t == UserAccountType.personal) {
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('First and last name are required.')),
        );
        return;
      }
    } else if (t == UserAccountType.nonprofit) {
      if (_entityName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization name is required.')),
        );
        return;
      }
    } else if (t == UserAccountType.business) {
      if (_entityName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business name is required.')),
        );
        return;
      }
    }
    final svc = context.read<UserProfileService>();
    try {
      await svc.updatePublicProfile(
        accountType: t,
        firstName: t == UserAccountType.personal ? _firstName.text : null,
        lastName: t == UserAccountType.personal ? _lastName.text : null,
        organizationName: t == UserAccountType.nonprofit ? _entityName.text : null,
        businessName: t == UserAccountType.business ? _entityName.text : null,
        photoUrl: p.photoUrl?.trim().isNotEmpty == true ? p.photoUrl : null,
        bio: _bio.text.trim().isEmpty ? null : _bio.text,
        neighborhoodLabel: p.neighborhoodLabel?.trim().isNotEmpty == true
            ? p.neighborhoodLabel
            : null,
        eventsAttended: p.eventsAttended,
        requestsFulfilled: p.requestsFulfilled,
        eventsProgressNote: p.eventsProgressNote,
        requestsProgressNote: p.requestsProgressNote,
        interests: _interests,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final profileStream = context.read<UserProfileService>().profileStream(widget.profile.uid);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: StreamBuilder<UserProfile?>(
          stream: profileStream,
          initialData: widget.profile,
          builder: (context, snap) {
            final live = snap.data ?? widget.profile;
            final at = live.accountType;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Edit profile',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                if (at == UserAccountType.personal) ...[
                  TextField(
                    controller: _firstName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'First name',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: 'Last name',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _entityName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: at == UserAccountType.nonprofit
                          ? 'Organization name'
                          : 'Business name',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _bio,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: UserProfileService.maxBioLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'A few words about you…',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                InterestsPicker(
                  selectedInterests: _interests,
                  onChanged: (interests) => setState(() => _interests = interests),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openSetHomeAreaWithProfile(live)),
                  icon: const Icon(Icons.location_city),
                  label: Text(
                    _homeAreaEditButtonLabel(live),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _headerGreen,
                    side: const BorderSide(color: _headerGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _headerGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save'),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _signOut(context),
                  icon: Icon(Icons.logout, size: 20, color: _slateSubtitle),
                  label: Text(
                    'Log out',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _slateSubtitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    Navigator.of(context).pop();
    context.read<AuthRedirect>().clear();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/sign-in');
  }
}

class _FollowStatsCard extends StatelessWidget {
  const _FollowStatsCard({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final followService = context.read<FollowService>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: StreamBuilder<int>(
              stream: followService.followerCountStream(userId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return _FollowStatColumn(
                  count: count,
                  label: 'FOLLOWERS',
                );
              },
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: const Color(0xFFE0E0E0),
          ),
          Expanded(
            child: StreamBuilder<int>(
              stream: followService.followingCountStream(userId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return _FollowStatColumn(
                  count: count,
                  label: 'FOLLOWING',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowStatColumn extends StatelessWidget {
  const _FollowStatColumn({
    required this.count,
    required this.label,
  });

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: _headerGreen,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B6B6B),
          ),
        ),
      ],
    );
  }
}
