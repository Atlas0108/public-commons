import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'didit_result.dart';

/// Same region as [functions/index.js] (`createDiditSession`).
const _diditFunctionsRegion = 'us-central1';

/// Web: create a Didit v3 session via Cloud Function (avoids browser CORS on Didit’s API).
Future<DiditResult> launchDiditVerification({
  required String workflowId,
  required String vendorData,
  String? apiKey,
  String? callbackUrl,
  String? portraitImageBase64,
}) async {
  // [apiKey] kept for a shared entrypoint signature; on web the key is Functions secret DIDIT_API_KEY.
  if (FirebaseAuth.instance.currentUser == null) {
    return const DiditSdkFailed('Sign in to start verification.');
  }

  final payload = <String, dynamic>{
    'workflowId': workflowId,
    'vendorData': vendorData,
    if (callbackUrl != null && callbackUrl.isNotEmpty) 'callbackUrl': callbackUrl,
    if (portraitImageBase64 != null && portraitImageBase64.isNotEmpty)
      'portraitImage': portraitImageBase64,
  };

  try {
    final functions = FirebaseFunctions.instanceFor(region: _diditFunctionsRegion);
    final callable = functions.httpsCallable('createDiditSession');
    final result = await callable.call(payload);
    final raw = result.data;
    if (raw is! Map) {
      return const DiditSdkFailed('Invalid response from createDiditSession.');
    }
    final data = Map<String, dynamic>.from(raw);
    final verifyUrl = data['url'] as String? ?? data['verification_url'] as String?;
    if (verifyUrl == null || verifyUrl.isEmpty) {
      return const DiditSdkFailed('Function response missing url.');
    }
    final sessionId = data['sessionId']?.toString();

    final uri = Uri.parse(verifyUrl);
    var opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!opened) {
      return DiditSdkFailed('Could not open verification URL.');
    }

    return DiditSdkCompleted(
      statusLabel: 'Verification opened',
      sessionId: sessionId,
    );
  } on FirebaseFunctionsException catch (e) {
    return DiditSdkFailed(e.message ?? e.code);
  } on Object catch (e) {
    return DiditSdkFailed(e.toString());
  }
}
