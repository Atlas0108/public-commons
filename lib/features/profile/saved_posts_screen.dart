import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/community_event.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/saved_posts_service.dart';
import '../../core/utils/event_formatting.dart';
import '../../widgets/close_to_shell.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  static String _kindLabel(PostKind k) {
    return switch (k) {
      PostKind.helpOffer => 'Offering help',
      PostKind.helpRequest => 'Requesting help',
      PostKind.communityEvent => 'Event',
      PostKind.bulletin => 'Bulletin',
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          actions: const [CloseToShellIconButton()],
        ),
        body: const Center(child: Text('Sign in to see saved posts.')),
      );
    }

    final savedSvc = context.read<SavedPostsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved'),
        actions: const [CloseToShellIconButton()],
      ),
      body: StreamBuilder<List<CommonsPost>>(
        stream: savedSvc.savedPostsFeed(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load saved posts.\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final posts = snap.data ?? [];
          final fmt = DateFormat.yMMMd().add_jm();

          final tiles = <Widget>[];
          for (final p in posts) {
            if (p.kind == PostKind.communityEvent) {
              final e = CommunityEvent.fromCommonsPost(p);
              if (e != null) {
                tiles.add(
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: Icon(Icons.event_outlined, color: Colors.deepOrange.shade700),
                      title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        'Event · ${formatEventScheduleLine(e)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/event/${p.id}'),
                    ),
                  ),
                );
              }
              continue;
            }
            tiles.add(
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Icon(Icons.article_outlined, color: Theme.of(context).colorScheme.primary),
                  title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${_kindLabel(p.kind)} · ${fmt.format(p.createdAt.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/posts/${p.id}'),
                ),
              ),
            );
          }

          if (tiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_border, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing saved yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use the bookmark on posts and events to save them here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => tiles[i],
          );
        },
      ),
    );
  }
}
