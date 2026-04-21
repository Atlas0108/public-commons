import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/models/post.dart';
import 'adaptive_post_cover_frame.dart';
import 'expanded_post_card.dart';
import 'post_author_row.dart';
import 'post_comment_button.dart';
import 'post_kind_icon_badge.dart';
import 'post_reaction_buttons.dart';
import 'post_save_button.dart';

const Color _categoryColor = Color(0xFF6B7B8C);
const Color _forestCategory = Color(0xFF4A6354);
const Color _arrowColor = Color(0xFF8E9499);
const Color _bodyColor = Color(0xFF5C6268);

Widget postFeedCardWithSave(String contentId, Widget editorialCard, {VoidCallback? onCommentTap}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      editorialCard,
      Positioned(
        right: 6,
        bottom: 6,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PostReactionButtons(postId: contentId, compact: true),
            const SizedBox(width: 6),
            PostCommentButton(postId: contentId, compact: true, onTap: onCommentTap),
            const SizedBox(width: 6),
            PostSaveButton(contentId: contentId),
          ],
        ),
      ),
    ],
  );
}

class PostFeedCard extends StatelessWidget {
  const PostFeedCard({super.key, required this.post});

  final CommonsPost post;

  String _descriptionPreview() {
    final b = post.body?.trim();
    if (b != null && b.isNotEmpty) {
      return b.replaceAll(RegExp(r'\s+'), ' ');
    }
    return 'Tap to read more.';
  }

  bool get _hasImage => post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;

  void _openDetail(BuildContext context) {
    openExpandedPostCard(context, post);
  }

  void _openCommentDetail(BuildContext context) {
    openExpandedPostCard(context, post, focusComments: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasImage) {
      return _buildImageHeroCard(context);
    }

    return postFeedCardWithSave(
      post.id,
      Hero(
        tag: 'post_card_${post.id}',
        child: EditorialCard(
          onTap: () => _openDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PostKindIconBadge(kind: post.kind),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.arrow_forward, size: 22, color: _arrowColor),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                postKindListHeadline(post.kind),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _categoryColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  fontSize: 11,
                ),
              ),
              if (post.status == PostStatus.fulfilled) ...[
                const SizedBox(height: 6),
                Text(
                  'FULFILLED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _categoryColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    fontSize: 10,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                post.displayTitleLine,
                style: GoogleFonts.lora(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: const Color(0xFF141414),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _descriptionPreview(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.45),
              ),
              const SizedBox(height: 20),
              PostAuthorTapRow(
                authorId: post.authorId,
                authorName: post.authorName,
                enableProfileTap: false,
              ),
            ],
          ),
        ),
      ),
      onCommentTap: () => _openCommentDetail(context),
    );
  }

  Widget _buildImageHeroCard(BuildContext context) {
    final url = post.imageUrl!.trim();

    return postFeedCardWithSave(
      post.id,
      Hero(
        tag: 'post_card_${post.id}',
        child: EditorialCard(
          onTap: () => _openDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AdaptivePostCoverFrame(
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return ColoredBox(
                        color: Colors.grey.shade200,
                        child: Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: Colors.grey.shade300,
                      child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600, size: 48),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          postKindListHeadline(post.kind),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _forestCategory,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            fontSize: 11,
                          ),
                        ),
                        if (post.status == PostStatus.fulfilled) ...[
                          const SizedBox(height: 4),
                          Text(
                            'FULFILLED',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _forestCategory,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PostKindIconBadge(kind: post.kind, compact: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.displayTitleLine,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: const Color(0xFF141414),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _descriptionPreview(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _bodyColor, height: 1.5, fontSize: 15),
              ),
              const SizedBox(height: 20),
              PostAuthorTapRow(
                authorId: post.authorId,
                authorName: post.authorName,
                enableProfileTap: false,
              ),
            ],
          ),
        ),
      ),
      onCommentTap: () => _openCommentDetail(context),
    );
  }
}

class EditorialCard extends StatelessWidget {
  const EditorialCard({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}
