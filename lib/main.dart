import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'core/platform/is_apple_mobile_web.dart';
import 'app/auth_redirect.dart';
import 'app/profile_gate_refresh.dart';
import 'app/app_router.dart';
import 'app/view_as_controller.dart';
import 'app/app_scaffold_messenger.dart';
import 'core/config/app_config.dart';
import 'core/app_google_fonts.dart';
import 'core/config/firebase_storage_factory.dart';
import 'core/app_trace.dart';
import 'core/services/connection_service.dart';
import 'core/services/event_service.dart';
import 'core/services/group_service.dart';
import 'core/services/messaging_service.dart';
import 'core/services/post_service.dart';
import 'core/services/post_reactions_service.dart';
import 'core/services/saved_posts_service.dart';
import 'core/services/user_profile_service.dart';
import 'features/auth/setup_screen.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Without this, `context.push('/posts/…')` keeps the browser URL on the shell
  // (e.g. /home) so shared links never include the post path. Web only.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  commonsTrace('main', 'WidgetsFlutterBinding done');
  runApp(const BootstrapSplash());
  try {
    await preloadAppGoogleFonts();
    await dotenv.load(fileName: '.env', isOptional: true);
    commonsTrace('main', 'dotenv loaded');
    if (isFirebaseConfigured) {
      commonsTrace('main', 'Firebase.initializeApp start');
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      commonsTrace('main', 'Firebase.initializeApp done');
      // Firestore (and other backends) with App Check *enforcement* reject clients with no token as permission-denied.
      if (kIsWeb) {
        final recaptchaSiteKey = dotenv.env['FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY']?.trim();
        final webProvider = kDebugMode
            ? WebDebugProvider()
            : (recaptchaSiteKey != null && recaptchaSiteKey.isNotEmpty
                ? ReCaptchaV3Provider(recaptchaSiteKey)
                : null);
        if (webProvider != null) {
          try {
            await FirebaseAppCheck.instance.activate(providerWeb: webProvider);
            await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
            commonsTrace(
              'main',
              kDebugMode
                  ? 'App Check: WebDebugProvider — add the browser debug token (devtools / console) under Firebase Console → App Check → Manage debug tokens if enforcement is on'
                  : 'App Check: ReCaptcha v3 active',
            );
          } on Object catch (e) {
            commonsTrace('main', 'FirebaseAppCheck.activate failed: $e');
          }
        } else if (!kDebugMode) {
          commonsTrace(
            'main',
            'App Check skipped (set FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY for release web if Firestore enforcement is on)',
          );
        }
      }
      // Mobile Safari often hangs or fails silently with IndexedDB + multi-tab persistence.
      // Use memory cache there so the app can render; other browsers keep disk persistence.
      if (kIsWeb && isAppleMobileWeb()) {
        FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
        commonsTrace('main', 'Firestore.settings: persistence off (Apple mobile web)');
      } else {
        // Web: IndexedDB persistence lets reads resolve from cache when offline.
        // Prefer auto long-polling detection; forcing long polling can leave some `set()` Futures
        // pending forever on web while the write still reaches the server (spinner never clears).
        FirebaseFirestore.instance.settings = Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          webExperimentalForceLongPolling: null,
          webExperimentalAutoDetectLongPolling: kIsWeb ? true : null,
          webPersistentTabManager: kIsWeb ? const WebPersistentMultipleTabManager() : null,
        );
        commonsTrace('main', 'Firestore.settings applied kIsWeb=$kIsWeb');
      }
    } else {
      commonsTrace('main', 'Firebase not configured (setup screen)');
    }
    commonsTrace('main', 'runApp');
    runApp(const PublicCommonsApp());
  } on Object catch (e, st) {
    commonsTrace('main', 'Bootstrap failed: $e\n$st');
    runApp(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          backgroundColor: AppTheme.publicCommonsCream,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not start Public Commons.\n\n$e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown immediately while [main] awaits Firebase, fonts, and env — loader only.
/// Web uses a matching spinner in `index.html` until `flutter-first-frame`.
class BootstrapSplash extends StatelessWidget {
  const BootstrapSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AppTheme.publicCommonsCream,
        body: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.publicCommonsForest,
              semanticsLabel: 'Loading',
            ),
          ),
        ),
      ),
    );
  }
}

class PublicCommonsApp extends StatelessWidget {
  const PublicCommonsApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isFirebaseConfigured) {
      return MaterialApp(
        title: 'Public Commons',
        theme: AppTheme.light(),
        home: const SetupScreen(),
      );
    }
    return const _FirebaseShell();
  }
}

class _FirebaseShell extends StatefulWidget {
  const _FirebaseShell();

  @override
  State<_FirebaseShell> createState() => _FirebaseShellState();
}

class _FirebaseShellState extends State<_FirebaseShell> {
  late final ProfileGateRefresh _profileGate;
  late final UserProfileService _userProfileService;
  late final PostService _postService;
  late final PostReactionsService _postReactionsService;
  late final SavedPostsService _savedPostsService;
  late final EventService _eventService;
  late final MessagingService _messagingService;
  late final ConnectionService _connectionService;
  late final GroupService _groupService;
  late final ViewAsController _viewAsController;
  late final AuthRedirect _authRedirect;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final storage = createFirebaseStorage();

    _authRedirect = AuthRedirect();
    _profileGate = ProfileGateRefresh(auth, firestore);
    _userProfileService = UserProfileService(firestore, auth, storage);
    _postService = PostService(firestore, auth, storage);
    _postReactionsService = PostReactionsService(firestore, auth);
    _savedPostsService = SavedPostsService(firestore, auth);
    _eventService = EventService(firestore, auth, storage);
    _messagingService = MessagingService(firestore, auth);
    _connectionService = ConnectionService(firestore, auth);
    _groupService = GroupService(firestore, auth);
    _viewAsController = ViewAsController(auth, _userProfileService);

    _router = createAppRouter(
      profileGateRefresh: _profileGate,
      authRedirect: _authRedirect,
    );
    _profileGate.attach();
  }

  @override
  void dispose() {
    _viewAsController.dispose();
    _profileGate.dispose();
    _authRedirect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<UserProfileService>.value(value: _userProfileService),
        Provider<PostService>.value(value: _postService),
        Provider<PostReactionsService>.value(value: _postReactionsService),
        Provider<SavedPostsService>.value(value: _savedPostsService),
        Provider<EventService>.value(value: _eventService),
        Provider<MessagingService>.value(value: _messagingService),
        Provider<ConnectionService>.value(value: _connectionService),
        Provider<GroupService>.value(value: _groupService),
        ChangeNotifierProvider<ViewAsController>.value(value: _viewAsController),
        ChangeNotifierProvider<AuthRedirect>.value(value: _authRedirect),
      ],
      child: _AuthProfileSync(
        child: MaterialApp.router(
          title: 'Public Commons',
          theme: AppTheme.light(),
          scaffoldMessengerKey: appScaffoldMessengerKey,
          routerConfig: _router,
        ),
      ),
    );
  }
}

/// Ensures `users/{uid}` exists whenever a session is restored or the signed-in user changes,
/// not only right after the sign-in form (which could navigate away before the write finished).
class _AuthProfileSync extends StatefulWidget {
  const _AuthProfileSync({required this.child});

  final Widget child;

  @override
  State<_AuthProfileSync> createState() => _AuthProfileSyncState();
}

class _AuthProfileSyncState extends State<_AuthProfileSync> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user == null) return;
      final email = user.email?.trim();
      if (email == null || email.isEmpty) return;
      final svc = context.read<UserProfileService>();
      unawaited(svc.ensureProfile(displayName: 'Neighbor'));
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
