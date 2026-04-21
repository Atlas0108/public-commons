import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/comments_service.dart';

class PostCommentButton extends StatelessWidget {
  const PostCommentButton({
    super.key,
    required this.postId,
    this.onTap,
    this.compact = false,
  });

  final String postId;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<CommentsService>();

    return StreamBuilder<int>(
      stream: svc.commentCountStream(postId),
      builder: (context, snap) {
        final count = snap.data ?? 0;

        if (compact) {
          return Material(
            color: Colors.white.withValues(alpha: 0.94),
            elevation: 1,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Color(0xFF6B7280),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(count),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Material(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatCount(count),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
