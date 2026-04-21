import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Create tab: options to create new content (posts, events, groups).
class CreateHubScreen extends StatelessWidget {
  const CreateHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
      ),
      body: const _NewCreateTab(),
    );
  }
}

class _NewCreateTab extends StatelessWidget {
  const _NewCreateTab();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'What would you like to create?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Events, help posts, or a group for neighbors to join.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            _CreateTypeCard(
              icon: Icons.event_available_outlined,
              iconColor: scheme.primary,
              title: 'Event',
              subtitle:
                  'Title, organizer, description, categories, schedule, and location or meeting link.',
              onTap: () => context.push('/post/new/event'),
            ),
            const SizedBox(height: 12),
            _CreateTypeCard(
              icon: Icons.handshake_outlined,
              iconColor: Colors.green.shade700,
              title: 'Offering help',
              subtitle: 'Something you can do or lend to neighbors.',
              onTap: () => context.push('/compose?kind=offer'),
            ),
            const SizedBox(height: 12),
            _CreateTypeCard(
              icon: Icons.support_agent_outlined,
              iconColor: Colors.blue.shade700,
              title: 'Requesting help',
              subtitle: 'Ask for a hand, tools, or local knowledge.',
              onTap: () => context.push('/compose?kind=request'),
            ),
            const SizedBox(height: 12),
            _CreateTypeCard(
              icon: Icons.groups_outlined,
              iconColor: scheme.tertiary,
              title: 'Group',
              subtitle:
                  'Public groups are visible to everyone. Private groups are only visible to members you invite.',
              onTap: () => context.push('/groups/new'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTypeCard extends StatelessWidget {
  const _CreateTypeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
