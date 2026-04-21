import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/public_commons_admin.dart';
import '../core/config/app_config.dart' show isFirebaseConfigured;
import '../core/models/post_kind.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/auth/session_loading_screen.dart';
import '../features/auth/setup_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/events/create_event_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/help_desk/compose_post_screen.dart';
import '../features/help_desk/post_detail_screen.dart';
import '../features/admin/admin_post_review_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/home/home_screen.dart';
import '../features/inbox/chat_screen.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/groups/create_group_screen.dart';
import '../features/groups/group_detail_screen.dart';
import '../features/groups/manage_groups_screen.dart';
import '../features/post/create_hub_screen.dart';
import '../features/profile/connection_requests_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/staff_screen.dart';
import 'auth_redirect.dart';
import 'profile_gate_refresh.dart';
import 'shell/app_shell.dart';
import 'shell/shell_tab_container.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter createAppRouter({
  required ProfileGateRefresh profileGateRefresh,
  required AuthRedirect authRedirect,
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: profileGateRefresh,
    redirect: (context, state) {
      if (!isFirebaseConfigured) {
        final p = state.uri.path;
        return (p == '/setup' || p == '/onboarding') ? null : '/setup';
      }

      final user = FirebaseAuth.instance.currentUser;
      final path = state.uri.path;

      if (user == null) {
        if (path != '/sign-in' &&
            path != '/sign-up' &&
            path != '/setup' &&
            path != '/onboarding') {
          authRedirect.captureFromUri(state.uri);
        }
        if (path == '/sign-in' ||
            path == '/sign-up' ||
            path == '/setup' ||
            path == '/onboarding') {
          return null;
        }
        return '/sign-in';
      }

      // Old app used /map, /feed, /events; bookmarks or hash routes may still point there.
      if (path == '/map' || path == '/feed' || path == '/events') {
        return '/home';
      }

      if (path == '/onboarding') {
        return null;
      }

      final complete = profileGateRefresh.setupComplete;

      // First Firestore snapshot not received yet — avoid flashing profile setup.
      if (complete == null) {
        if (path == '/session-loading') return null;
        return '/session-loading';
      }

      if (complete == false) {
        if (path == '/profile-setup') return null;
        return '/profile-setup';
      }

      if (path == '/profile-setup' ||
          path == '/sign-in' ||
          path == '/sign-up' ||
          path == '/setup' ||
          path == '/session-loading') {
        final target = sanitizeRedirectForNavigation(authRedirect.consume()) ?? '/home';
        return target;
      }

      if (complete == true) {
        authRedirect.clearIfReached(path);
      }

      if ((path == '/admin' || path.startsWith('/admin/')) &&
          !isPublicCommonsAdminEmail(user.email)) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/home',
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(registering: false),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignInScreen(registering: true),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/session-loading',
        builder: (context, state) => const SessionLoadingScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: shellTabContainerBuilder,
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/post',
                builder: (context, state) {
                  final tab = state.uri.queryParameters['tab'] ?? '';
                  var idx = 0;
                  if (tab == 'my' || tab == 'content' || tab == '1') {
                    idx = 1;
                  } else if (tab == 'saved' || tab == '2') {
                    idx = 2;
                  }
                  return CreateHubScreen(initialTabIndex: idx);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/compose',
        builder: (context, state) {
          final kind = state.uri.queryParameters['kind'];
          final gid = state.uri.queryParameters['groupId']?.trim();
          PostKind? initial;
          if (kind == 'offer') initial = PostKind.helpOffer;
          if (kind == 'request') initial = PostKind.helpRequest;
          final bulletin = kind == 'bulletin';
          return ComposePostScreen(
            initialDeskKind: bulletin ? null : initial,
            groupId: gid != null && gid.isNotEmpty ? gid : null,
            bulletinMode: bulletin,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/groups/new',
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/groups/manage',
        builder: (context, state) => const ManageGroupsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/groups/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return GroupDetailScreen(groupId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/post/new/event',
        builder: (context, state) {
          final gid = state.uri.queryParameters['groupId']?.trim();
          return CreateEventScreen(
            groupId: gid != null && gid.isNotEmpty ? gid : null,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/posts/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ComposePostScreen(editingPostId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/posts/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PostDetailScreen(postId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/admin/review/post/:postId',
        builder: (context, state) {
          final id = state.pathParameters['postId']!;
          return AdminPostReviewScreen(postId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/u/:userId',
        builder: (context, state) {
          final uid = state.pathParameters['userId']!;
          return ProfileScreen(userId: uid);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/connections',
        builder: (context, state) => const ConnectionRequestsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/staff',
        builder: (context, state) => const StaffScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/chat/:conversationId',
        builder: (context, state) {
          final id = state.pathParameters['conversationId']!;
          final extra = state.extra as ChatScreenRouteExtra?;
          return ChatScreen(conversationId: id, routeExtra: extra);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/new',
        redirect: (context, state) => '/post/new/event',
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CreateEventScreen(editingEventId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return EventDetailScreen(eventId: id);
        },
      ),
    ],
  );
}
