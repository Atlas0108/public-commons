import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/post.dart';
import '../core/models/post_kind.dart';
import '../core/models/rsvp.dart';
import '../core/services/event_service.dart';
import '../core/utils/link_utils.dart';
import 'adaptive_post_cover_frame.dart';
import 'message_poster_button.dart';
import 'post_author_row.dart';
import 'post_comment_button.dart';
import 'post_comments_section.dart';
import 'post_kind_icon_badge.dart';
import 'post_reaction_buttons.dart';
import 'post_save_button.dart';

void openExpandedPostCard(BuildContext context, CommonsPost post, {bool focusComments = false}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ExpandedPostCard(post: post, focusComments: focusComments);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    ),
  );
}

class ExpandedPostCard extends StatefulWidget {
  const ExpandedPostCard({super.key, required this.post, this.focusComments = false});

  final CommonsPost post;
  final bool focusComments;

  @override
  State<ExpandedPostCard> createState() => _ExpandedPostCardState();
}

class _ExpandedPostCardState extends State<ExpandedPostCard> {
  final _scrollController = ScrollController();
  final _commentsKey = GlobalKey();
  final _commentInputFocusNode = FocusNode();

  static const _bodyColor = Color(0xFF5C6268);

  @override
  void dispose() {
    _scrollController.dispose();
    _commentInputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToComments() {
    final context = _commentsKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        _commentInputFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = FirebaseAuth.instance.currentUser;
    final isAuthor = user?.uid == post.authorId;
    final hasImage = post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;
    final imageUrl = hasImage ? post.imageUrl!.trim() : '';
    final padding = MediaQuery.paddingOf(context);

    return Hero(
      tag: 'post_card_${post.id}',
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(24, padding.top + 56, 24, padding.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AdaptivePostCoverFrame(
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return ColoredBox(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: Colors.grey.shade300,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey.shade600,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (post.kind != PostKind.bulletin) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        PostKindIconBadge(kind: post.kind),
                        const SizedBox(width: 12),
                        Text(
                          postKindListHeadline(post.kind),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF6B7B8C),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                                fontSize: 11,
                              ),
                        ),
                        if (post.status == PostStatus.fulfilled) ...[
                          const SizedBox(width: 12),
                          Chip(
                            label: const Text('Fulfilled'),
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (post.kind == PostKind.bulletin) ...[
                    if (post.body != null && post.body!.trim().isNotEmpty)
                      Text(
                        post.body!.trim(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              height: 1.45,
                            ),
                      )
                    else if (post.title.trim().isNotEmpty)
                      Text(
                        post.title.trim(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              height: 1.45,
                            ),
                      ),
                  ] else ...[
                    Text(
                      post.title,
                      style: hasImage
                          ? GoogleFonts.playfairDisplay(
                              fontSize: 28,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              color: const Color(0xFF141414),
                            )
                          : GoogleFonts.lora(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: const Color(0xFF141414),
                            ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    DateFormat.yMMMd().add_jm().format(post.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _bodyColor,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: PostAuthorTapRow(
                          authorId: post.authorId,
                          authorName: post.authorName,
                          avatarRadius: 20,
                          textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      MessagePosterButton(
                        authorId: post.authorId,
                        authorName: post.authorName,
                      ),
                    ],
                  ),
                  if (post.kind == PostKind.communityEvent && post.startsAt != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatEventSchedule(post),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _bodyColor,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (post.kind == PostKind.communityEvent &&
                      post.locationDescription != null &&
                      post.locationDescription!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: _LocationBlock(text: post.locationDescription!)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      PostReactionButtons(postId: post.id),
                      const SizedBox(width: 8),
                      PostCommentButton(
                        postId: post.id,
                        onTap: _scrollToComments,
                      ),
                      const SizedBox(width: 8),
                      PostSaveButton(contentId: post.id),
                    ],
                  ),
                  if (post.kind != PostKind.bulletin &&
                      post.body != null &&
                      post.body!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      post.body!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _bodyColor,
                            height: 1.6,
                            fontSize: 16,
                          ),
                    ),
                  ],
                  if (post.kind == PostKind.communityEvent && user != null) ...[
                    const SizedBox(height: 28),
                    Text('RSVP', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _RsvpRow(eventId: post.id),
                  ],
                  if (isAuthor) ...[
                    const SizedBox(height: 32),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pop();
                        if (post.kind == PostKind.communityEvent) {
                          context.push('/event/${post.id}/edit');
                        } else {
                          context.push('/posts/${post.id}/edit');
                        }
                      },
                      child: Text(post.kind == PostKind.communityEvent ? 'Edit Event' : 'Edit Post'),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 24),
                  PostCommentsSection(
                    key: _commentsKey,
                    postId: post.id,
                    autofocus: widget.focusComments,
                    inputFocusNode: _commentInputFocusNode,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            Positioned(
              top: padding.top + 8,
              right: 12,
              child: Material(
                color: Colors.grey.shade100,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.close, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEventSchedule(CommonsPost post) {
    final start = post.startsAt?.toLocal();
    if (start == null) return '';
    final end = post.endsAt?.toLocal();
    if (end == null) return DateFormat.yMMMd().add_jm().format(start);
    final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    if (sameDay) {
      return '${DateFormat.yMMMd().add_jm().format(start)} – ${DateFormat.jm().format(end)}';
    }
    return '${DateFormat.yMMMd().add_jm().format(start)} – ${DateFormat.yMMMd().add_jm().format(end)}';
  }
}

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.text});

  final String text;

  Future<void> _open() async {
    final uri = Uri.parse(text.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (locationTextLooksLikeHttpUrl(text)) {
      return InkWell(
        onTap: _open,
        child: Text(
          text.trim(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
        ),
      );
    }
    return SelectableText(
      text.trim(),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF5C6268),
      ),
    );
  }
}

class _RsvpRow extends StatelessWidget {
  const _RsvpRow({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    final eventService = context.read<EventService>();
    return StreamBuilder<EventRsvp?>(
      stream: eventService.myRsvpStream(eventId),
      builder: (context, snap) {
        final current = snap.data?.status;
        return Row(
          children: [
            Expanded(
              child: _RsvpSegment(
                label: 'Going',
                selected: current == RsvpStatus.going,
                onPressed: () => eventService.setMyRsvp(eventId, RsvpStatus.going),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RsvpSegment(
                label: 'Maybe',
                selected: current == RsvpStatus.maybe,
                onPressed: () => eventService.setMyRsvp(eventId, RsvpStatus.maybe),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RsvpSegment(
                label: "Can't go",
                selected: current == RsvpStatus.declined,
                onPressed: () => eventService.setMyRsvp(eventId, RsvpStatus.declined),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RsvpSegment extends StatelessWidget {
  const _RsvpSegment({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        minimumSize: const Size(0, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    );
  }
}
