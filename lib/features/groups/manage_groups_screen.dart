import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/group.dart';
import '../../core/services/group_service.dart';
import '../../widgets/close_to_shell.dart';

/// Lists groups the signed-in user belongs to; create new ones from here.
class ManageGroupsScreen extends StatelessWidget {
  const ManageGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat.yMMMd().add_jm();

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Manage groups'),
          actions: const [CloseToShellIconButton()],
        ),
        body: const Center(child: Text('Sign in to manage groups.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage groups'),
        actions: const [CloseToShellIconButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: FilledButton.icon(
              onPressed: () => context.push('/groups/new'),
              icon: const Icon(Icons.add),
              label: const Text('New group'),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CommonsGroup>>(
              stream: context.read<GroupService>().myGroupsStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load groups.\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final groups = snap.data ?? [];
                if (groups.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, size: 56, color: scheme.outline),
                          const SizedBox(height: 20),
                          Text(
                            'No groups yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a public or private group. You can invite neighbors from connections on private groups.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final g = groups[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Icon(Icons.groups_outlined, color: scheme.tertiary),
                        title: Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${g.isPublic ? 'Public' : 'Private'} · ${fmt.format(g.createdAt.toLocal())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/groups/${g.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
