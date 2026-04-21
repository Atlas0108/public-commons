import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/models/post.dart';
import '../core/models/post_kind.dart';
import 'adaptive_post_cover_frame.dart';
import 'message_poster_button.dart';
import 'post_author_row.dart';
import 'post_kind_icon_badge.dart';
import 'post_reaction_buttons.dart';
import 'post_save_button.dart';

void openExpandedPostCard(BuildContext context, CommonsPost post) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ExpandedPostCard(post: post);
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

class ExpandedPostCard extends StatelessWidget {
  const ExpandedPostCard({super.key, required this.post});

  final CommonsPost post;

  static const _bodyColor = Color(0xFF5C6268);

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      PostReactionButtons(postId: post.id),
                      const SizedBox(width: 12),
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
                  if (isAuthor) ...[
                    const SizedBox(height: 32),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pop();
                        context.push('/posts/${post.id}/edit');
                      },
                      child: const Text('Edit Post'),
                    ),
                  ],
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
}
