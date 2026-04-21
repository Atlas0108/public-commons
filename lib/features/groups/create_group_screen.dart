import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_scaffold_messenger.dart' show appScaffoldMessengerKey;
import '../../core/models/group.dart';
import '../../core/models/user_connection.dart';
import '../../core/services/connection_service.dart';
import '../../core/services/group_service.dart';
import '../../widgets/close_to_shell.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  GroupVisibility _visibility = GroupVisibility.public;
  final Set<String> _selectedPeerIds = {};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      appScaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Sign in to create a group.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final svc = context.read<GroupService>();
      final id = await svc.createGroup(
        name: _name.text,
        description: _description.text,
        visibility: _visibility,
        additionalMemberIds: _selectedPeerIds.toList(),
      );
      if (!mounted) return;
      context.go('/groups/$id');
    } on Object catch (e) {
      if (!mounted) return;
      appScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Could not create group: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: const [CloseToShellIconButton()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
              maxLength: 120,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter a name';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              maxLength: 2000,
            ),
            const SizedBox(height: 24),
            Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<GroupVisibility>(
              segments: const [
                ButtonSegment(
                  value: GroupVisibility.public,
                  label: Text('Public'),
                  icon: Icon(Icons.public_outlined),
                ),
                ButtonSegment(
                  value: GroupVisibility.private,
                  label: Text('Private'),
                  icon: Icon(Icons.lock_outline),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) => setState(() => _visibility = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _visibility == GroupVisibility.public
                  ? 'Anyone signed in can view this group.'
                  : 'Only people you add to the group can view it. Add neighbors from your connections below, or create the group first and invite them from the group page.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (_visibility == GroupVisibility.private) ...[
              const SizedBox(height: 24),
              Text('Invite from connections', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              StreamBuilder<List<UserConnection>>(
                stream: context.read<ConnectionService>().myConnectionsStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return Text(
                      'No connections yet. Connect with neighbors from their profiles, then invite them here.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    );
                  }
                  return Column(
                    children: [
                      for (final c in list)
                        CheckboxListTile(
                          value: _selectedPeerIds.contains(c.peerId),
                          onChanged: (on) {
                            setState(() {
                              if (on == true) {
                                _selectedPeerIds.add(c.peerId);
                              } else {
                                _selectedPeerIds.remove(c.peerId);
                              }
                            });
                          },
                          title: Text(c.peerDisplayName),
                          subtitle: Text('Neighbor', style: TextStyle(color: scheme.onSurfaceVariant)),
                          secondary: Icon(Icons.person_outline, color: scheme.primary),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}
