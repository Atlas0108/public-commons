import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/post_reaction.dart';
import '../core/services/post_reactions_service.dart';

class PostReactionButtons extends StatefulWidget {
  const PostReactionButtons({
    super.key,
    required this.postId,
    this.compact = false,
  });

  final String postId;
  final bool compact;

  @override
  State<PostReactionButtons> createState() => _PostReactionButtonsState();
}

class _PostReactionButtonsState extends State<PostReactionButtons> {
  ReactionType? _optimisticReaction;
  ReactionCounts? _optimisticCounts;
  bool _hasOptimisticUpdate = false;

  void _handleLike(ReactionType? currentReaction, ReactionCounts currentCounts) {
    final svc = context.read<PostReactionsService>();
    
    final wasLiked = currentReaction == ReactionType.like;
    final wasDisliked = currentReaction == ReactionType.dislike;
    
    setState(() {
      _hasOptimisticUpdate = true;
      if (wasLiked) {
        _optimisticReaction = null;
        _optimisticCounts = ReactionCounts(
          likes: currentCounts.likes - 1,
          dislikes: currentCounts.dislikes,
        );
      } else {
        _optimisticReaction = ReactionType.like;
        _optimisticCounts = ReactionCounts(
          likes: currentCounts.likes + 1,
          dislikes: wasDisliked ? currentCounts.dislikes - 1 : currentCounts.dislikes,
        );
      }
    });

    svc.like(widget.postId).then((_) {
      if (mounted) setState(() => _hasOptimisticUpdate = false);
    }).catchError((e) {
      if (mounted) {
        setState(() => _hasOptimisticUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reaction: $e')),
        );
      }
    });
  }

  void _handleDislike(ReactionType? currentReaction, ReactionCounts currentCounts) {
    final svc = context.read<PostReactionsService>();
    
    final wasLiked = currentReaction == ReactionType.like;
    final wasDisliked = currentReaction == ReactionType.dislike;
    
    setState(() {
      _hasOptimisticUpdate = true;
      if (wasDisliked) {
        _optimisticReaction = null;
        _optimisticCounts = ReactionCounts(
          likes: currentCounts.likes,
          dislikes: currentCounts.dislikes - 1,
        );
      } else {
        _optimisticReaction = ReactionType.dislike;
        _optimisticCounts = ReactionCounts(
          likes: wasLiked ? currentCounts.likes - 1 : currentCounts.likes,
          dislikes: currentCounts.dislikes + 1,
        );
      }
    });

    svc.dislike(widget.postId).then((_) {
      if (mounted) setState(() => _hasOptimisticUpdate = false);
    }).catchError((e) {
      if (mounted) {
        setState(() => _hasOptimisticUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save reaction: $e')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final svc = context.read<PostReactionsService>();

    return StreamBuilder<ReactionType?>(
      stream: svc.myReactionStream(widget.postId),
      builder: (context, myReactionSnap) {
        final serverReaction = myReactionSnap.data;

        return StreamBuilder<ReactionCounts>(
          stream: svc.reactionCountsStream(widget.postId),
          builder: (context, countsSnap) {
            final serverCounts = countsSnap.data ?? const ReactionCounts();
            
            final displayReaction = _hasOptimisticUpdate ? _optimisticReaction : serverReaction;
            final displayCounts = _hasOptimisticUpdate ? (_optimisticCounts ?? serverCounts) : serverCounts;

            if (widget.compact) {
              return _CompactReactionButtons(
                myReaction: displayReaction,
                counts: displayCounts,
                onLike: () => _handleLike(serverReaction, serverCounts),
                onDislike: () => _handleDislike(serverReaction, serverCounts),
              );
            }

            return _FullReactionButtons(
              myReaction: displayReaction,
              counts: displayCounts,
              onLike: () => _handleLike(serverReaction, serverCounts),
              onDislike: () => _handleDislike(serverReaction, serverCounts),
            );
          },
        );
      },
    );
  }
}

class _CompactReactionButtons extends StatelessWidget {
  const _CompactReactionButtons({
    required this.myReaction,
    required this.counts,
    required this.onLike,
    required this.onDislike,
  });

  final ReactionType? myReaction;
  final ReactionCounts counts;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final isLiked = myReaction == ReactionType.like;
    final isDisliked = myReaction == ReactionType.dislike;

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
            onTap: onLike,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                    color: isLiked ? const Color(0xFF4A6354) : const Color(0xFF6B7280),
                  ),
                  if (counts.likes > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(counts.likes),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isLiked ? const Color(0xFF4A6354) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: Colors.grey.shade300,
          ),
          InkWell(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
            onTap: onDislike,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                    size: 18,
                    color: isDisliked ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                  ),
                  if (counts.dislikes > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(counts.dislikes),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDisliked ? const Color(0xFFDC2626) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullReactionButtons extends StatelessWidget {
  const _FullReactionButtons({
    required this.myReaction,
    required this.counts,
    required this.onLike,
    required this.onDislike,
  });

  final ReactionType? myReaction;
  final ReactionCounts counts;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  @override
  Widget build(BuildContext context) {
    final isLiked = myReaction == ReactionType.like;
    final isDisliked = myReaction == ReactionType.dislike;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ReactionButton(
          icon: isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
          label: _formatCount(counts.likes),
          isActive: isLiked,
          activeColor: const Color(0xFF4A6354),
          onTap: onLike,
        ),
        const SizedBox(width: 8),
        _ReactionButton(
          icon: isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
          label: _formatCount(counts.dislikes),
          isActive: isDisliked,
          activeColor: const Color(0xFFDC2626),
          onTap: onDislike,
        ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : const Color(0xFF6B7280);

    return Material(
      color: isActive ? activeColor.withValues(alpha: 0.1) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  } else if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return count.toString();
}
