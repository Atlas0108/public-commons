import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/default_geo.dart';
import '../../core/geo/geo_utils.dart';
import '../../core/app_trace.dart';
import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/event_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import 'feed_browse_location_sheet.dart';
import 'public_commons_invite_sheet.dart';
import '../../widgets/post_feed_card.dart';
import '../../widgets/post_kind_icon_badge.dart';

/// Home: community events and help-desk posts (newest first), with category tabs.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  static const _pageBackground = Color(0xFFF9F7F2);

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  void _openFeedBrowseSheet(BuildContext context, UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FeedBrowseLocationSheet(profile: profile),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: _pageBackground,
        body: SafeArea(child: Center(child: Text('Sign in to view the home feed.'))),
      );
    }

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: context.read<UserProfileService>().profileStream(user.uid),
          builder: (context, profileSnap) {
            final profile = profileSnap.data;
            final browseCenter = profile?.feedBrowseCenter(kDefaultGeoPoint) ?? kDefaultGeoPoint;
            final radiusMiles = (profile?.discoveryRadiusMiles ?? 25).toDouble();
            final browseLabel = profile?.feedBrowseLabel(kDefaultGeoPoint) ?? 'San Francisco area';

            return StreamBuilder<List<CommunityEvent>>(
              stream: context.read<EventService>().homeEventsFeed(),
              builder: (context, eventSnap) {
                return StreamBuilder<List<CommonsPost>>(
                  stream: context.read<PostService>().homePostsFeed(),
                  builder: (context, postSnap) {
                    final postWaiting =
                        !postSnap.hasData && postSnap.connectionState == ConnectionState.waiting;

                    if (eventSnap.hasError || postSnap.hasError) {
                      commonsTrace(
                        'HomeScreen feed error',
                        '${eventSnap.error ?? ''} ${postSnap.error ?? ''}'.trim(),
                      );
                      return ColoredBox(
                        color: _pageBackground,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          children: [
                            _EventsHero(onMakePost: () => context.go('/post')),
                            const SizedBox(height: 24),
                            Text(
                              'Could not load the feed.\n'
                              '${eventSnap.error ?? postSnap.error}',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    final rawEvents = eventSnap.data ?? [];
                    final rawPosts = postSnap.data ?? [];
                    final events = rawEvents
                        .where((e) => withinRadiusMiles(browseCenter, e.geoPoint, radiusMiles))
                        .toList();
                    final posts = rawPosts
                        .where((p) => !p.isGroupPost)
                        .where((p) => withinRadiusMiles(browseCenter, p.geoPoint, radiusMiles))
                        .toList();
                    final entries = _buildFeedEntries(context, events, posts, postWaiting: postWaiting);

                    return NestedScrollView(
                      headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
                        return [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4, top: 4),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  tooltip: 'Invite someone',
                                  icon: const Icon(Icons.person_add_outlined),
                                  onPressed: () => showPublicCommonsInviteSheet(context),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                              child: _EventsHero(onMakePost: () => context.go('/post')),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 20)),
                          SliverOverlapAbsorber(
                            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                            sliver: SliverPersistentHeader(
                              pinned: true,
                              delegate: _PinnedHomeFeedHeaderDelegate(
                                scheme: scheme,
                                backgroundColor: _pageBackground,
                                tabController: _tabController,
                                browseLabel: browseLabel,
                                onBrowseTap: profile == null ? null : () => _openFeedBrowseSheet(context, profile),
                                innerBoxIsScrolled: innerBoxIsScrolled,
                              ),
                            ),
                          ),
                        ];
                      },
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          for (var t = 0; t < 4; t++)
                            _HomeFeedTabScrollView(
                              tabIndex: t,
                              entries: entries,
                              scheme: scheme,
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum _FeedEntryKind { event, offer, request, skeleton }

class _FeedEntry {
  _FeedEntry({required this.at, required this.card, required this.kind});

  final DateTime at;
  final Widget card;
  final _FeedEntryKind kind;
}

List<_FeedEntry> _buildFeedEntries(
  BuildContext context,
  List<CommunityEvent> events,
  List<CommonsPost> posts, {
  required bool postWaiting,
}) {
  final entries = <_FeedEntry>[];
  // Convert legacy events to posts and use the same card
  for (var i = 0; i < events.length; i++) {
    final post = CommonsPost.fromEvent(events[i]);
    entries.add(
      _FeedEntry(
        at: post.createdAt,
        card: PostFeedCard(post: post),
        kind: _FeedEntryKind.event,
      ),
    );
  }
  for (var i = 0; i < posts.length; i++) {
    final p = posts[i];
    final kind = switch (p.kind) {
      PostKind.communityEvent => _FeedEntryKind.event,
      PostKind.helpOffer => _FeedEntryKind.offer,
      _ => _FeedEntryKind.request,
    };
    entries.add(
      _FeedEntry(
        at: p.createdAt,
        card: PostFeedCard(post: p),
        kind: kind,
      ),
    );
  }
  if (postWaiting) {
    final anchor = DateTime.now();
    for (var i = 0; i < 2; i++) {
      entries.add(
        _FeedEntry(
          at: anchor.add(Duration(microseconds: i)),
          card: const _PostFeedCardSkeleton(),
          kind: _FeedEntryKind.skeleton,
        ),
      );
    }
  }
  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries;
}

/// Soft peach for event date tiles on the feed (matches [_EventFeedCard]).
const Color kHomeEventDateBadgeBackground = Color(0xFFFFE8E0);

/// 0 All, 1 Events, 2 Offers, 3 Requests
List<_FeedEntry> _filterEntries(List<_FeedEntry> entries, int tabIndex) {
  return switch (tabIndex) {
    0 => entries,
    1 => entries.where((e) => e.kind == _FeedEntryKind.event).toList(),
    2 => entries.where((e) => e.kind == _FeedEntryKind.offer).toList(),
    3 => entries.where((e) => e.kind == _FeedEntryKind.request).toList(),
    _ => entries,
  };
}

class _HomeFeedTabScrollView extends StatefulWidget {
  const _HomeFeedTabScrollView({
    required this.tabIndex,
    required this.entries,
    required this.scheme,
  });

  final int tabIndex;
  final List<_FeedEntry> entries;
  final ColorScheme scheme;

  @override
  State<_HomeFeedTabScrollView> createState() => _HomeFeedTabScrollViewState();
}

class _HomeFeedTabScrollViewState extends State<_HomeFeedTabScrollView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filterEntries(widget.entries, widget.tabIndex);
    final rows = filtered.map((e) => e.card).toList();

    return CustomScrollView(
      key: PageStorageKey<String>('home_feed_tab_${widget.tabIndex}'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyFilterState(tabIndex: widget.tabIndex, scheme: widget.scheme),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                  child: rows[i],
                ),
                childCount: rows.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.tabIndex, required this.scheme});

  final int tabIndex;
  final ColorScheme scheme;

  String get _title => switch (tabIndex) {
    1 => 'No events yet',
    2 => 'No offers yet',
    3 => 'No requests yet',
    _ => 'Nothing here yet',
  };

  String get _subtitle => switch (tabIndex) {
    1 => 'Create an event from the Post tab.',
    2 => 'Share what you can do from the Post tab.',
    3 => 'Ask for a hand from the Post tab.',
    _ => 'Tap Make a post above, or use the Post tab.',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selected pill matches feed card chrome; each tab has a distinct label color.
class _HomeFeedFilterTabPalette {
  const _HomeFeedFilterTabPalette({required this.indicator, required this.selectedLabel});

  final Color indicator;
  final Color selectedLabel;
}

/// Order: All, Events, Offers, Requests.
final List<_HomeFeedFilterTabPalette> _homeFeedFilterTabPalettes = [
  const _HomeFeedFilterTabPalette(
    indicator: Color(0xFFE5E8EE),
    selectedLabel: Color(0xFF4A5B6C),
  ),
  _HomeFeedFilterTabPalette(
    indicator: kHomeEventDateBadgeBackground,
    selectedLabel: kPostKindIconColor,
  ),
  _HomeFeedFilterTabPalette(
    indicator: postKindIconBadgeBackground(PostKind.helpOffer),
    selectedLabel: const Color(0xFF395648),
  ),
  _HomeFeedFilterTabPalette(
    indicator: postKindIconBadgeBackground(PostKind.helpRequest),
    selectedLabel: const Color(0xFF6B4A78),
  ),
];

class _HomeFeedFilterTabRow extends StatelessWidget {
  const _HomeFeedFilterTabRow({
    required this.controller,
    required this.scheme,
    required this.palettes,
    required this.labels,
  });

  final TabController controller;
  final ColorScheme scheme;
  final List<_HomeFeedFilterTabPalette> palettes;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    assert(palettes.length == labels.length);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final idx = controller.index;
        return Row(
          children: List.generate(labels.length, (i) {
            final selected = idx == i;
            final pal = palettes[i];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (controller.index != i) controller.animateTo(i);
                    },
                    borderRadius: BorderRadius.circular(10),
                    splashColor: pal.indicator.withValues(alpha: 0.35),
                    highlightColor: pal.indicator.withValues(alpha: 0.2),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected ? pal.indicator : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              fontSize: 14,
                              color: selected ? pal.selectedLabel : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _PinnedHomeFeedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHomeFeedHeaderDelegate({
    required this.scheme,
    required this.backgroundColor,
    required this.tabController,
    required this.browseLabel,
    required this.onBrowseTap,
    required this.innerBoxIsScrolled,
  });

  final ColorScheme scheme;
  final Color backgroundColor;
  final TabController tabController;
  final String browseLabel;
  final VoidCallback? onBrowseTap;
  final bool innerBoxIsScrolled;

  static const double _locationRowHeight = 52;
  static const double _dividerHeight = 1;
  static const double _tabBarTopGap = 8;
  static const double _tabBarHeight = 48;
  static const double _tabBarBottomGap = 10;

  static const _forest = Color(0xFF4A6354);

  static const _filterTabLabels = ['All', 'Events', 'Offers', 'Requests'];

  @override
  double get minExtent =>
      _locationRowHeight +
      _dividerHeight +
      _tabBarTopGap +
      _tabBarHeight +
      _tabBarBottomGap;

  @override
  double get maxExtent =>
      _locationRowHeight +
      _dividerHeight +
      _tabBarTopGap +
      _tabBarHeight +
      _tabBarBottomGap;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final showShadow = innerBoxIsScrolled || overlapsContent;
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
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _locationRowHeight,
              child: InkWell(
                onTap: onBrowseTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 22, color: scheme.onSurface.withValues(alpha: 0.75)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            browseLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _forest,
                            ),
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
            SizedBox(height: _tabBarTopGap),
            SizedBox(
              height: _tabBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _HomeFeedFilterTabRow(
                  controller: tabController,
                  scheme: scheme,
                  palettes: _homeFeedFilterTabPalettes,
                  labels: _filterTabLabels,
                ),
              ),
            ),
            SizedBox(height: _tabBarBottomGap),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHomeFeedHeaderDelegate oldDelegate) {
    return scheme != oldDelegate.scheme ||
        backgroundColor != oldDelegate.backgroundColor ||
        tabController != oldDelegate.tabController ||
        browseLabel != oldDelegate.browseLabel ||
        onBrowseTap != oldDelegate.onBrowseTap ||
        innerBoxIsScrolled != oldDelegate.innerBoxIsScrolled;
  }
}

class _EventsHero extends StatelessWidget {
  const _EventsHero({required this.onMakePost});

  final VoidCallback onMakePost;

  static const _forest = Color(0xFF4A6354);
  static const _commons = Color(0xFF2E2D4D);
  static const _descriptionColor = Color(0xFF4A4F54);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontFamily: 'ResolideSerif',
              fontSize: 40,
              fontWeight: FontWeight.w400,
              height: 1.08,
            ),
            children: [
              TextSpan(text: 'Public ', style: TextStyle(color: _forest)),
              TextSpan(text: 'Commons', style: TextStyle(color: _commons)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'A platform designed to nourish the soul, tend to our communities, and strengthen our collective roots.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: _descriptionColor, height: 1.55, fontSize: 16),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _forest,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: onMakePost,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(Icons.add, color: _forest, size: 22),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Make a post',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PostFeedCardSkeleton extends StatelessWidget {
  const _PostFeedCardSkeleton();

  static const _bone = Color(0xFFE4E2DD);

  @override
  Widget build(BuildContext context) {
    Widget boneLine(double height, {double? width}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: _bone, borderRadius: BorderRadius.circular(6)),
      );
    }

    return IgnorePointer(
      child: EditorialCard(
        onTap: () {},
        child: Shimmer.fromColors(
          baseColor: _bone,
          highlightColor: Colors.white,
          period: const Duration(milliseconds: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 52,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _bone,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _bone,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              boneLine(10, width: 96),
              const SizedBox(height: 14),
              boneLine(22),
              const SizedBox(height: 10),
              boneLine(14),
              const SizedBox(height: 8),
              boneLine(14),
              const SizedBox(height: 8),
              boneLine(14, width: 200),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: _bone, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: boneLine(14)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

