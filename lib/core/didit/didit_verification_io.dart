import 'dart:io' show Platform;

import 'package:didit_sdk/sdk_flutter.dart';
import 'package:flutter/foundation.dart';

import 'didit_result.dart';

Future<DiditResult> launchDiditVerification({
  required String workflowId,
  required String vendorData,
  String? apiKey,
  String? callbackUrl,
  String? portraitImageBase64,
}) async {
  // Web builds use [didit_verification_web.dart] instead of this file.
  if (kIsWeb) {
    return const DiditUnsupported('Web is not supported by the native Didit SDK.');
  }
  // [apiKey] / [callbackUrl] are only used on web (Cloud Function + callback).
  if (!Platform.isAndroid && !Platform.isIOS) {
    return const DiditUnsupported(
      'Didit verification is only available on iOS and Android in this app.',
    );
  }

  try {
    final result = await DiditSdk.startVerificationWithWorkflow(
      workflowId,
      vendorData: vendorData,
    );

    switch (result) {
      case VerificationCompleted(:final session):
        final label = switch (session.status) {
          VerificationStatus.approved => 'Approved',
          VerificationStatus.pending => 'Pending review',
          VerificationStatus.declined => 'Declined',
        };
        return DiditSdkCompleted(
          statusLabel: label,
          sessionId: session.sessionId,
        );
      case VerificationCancelled():
        return const DiditSdkCancelled();
      case VerificationFailed(:final error):
        return DiditSdkFailed('${error.type.name}: ${error.message}');
    }
  } on Object catch (e) {
    return DiditSdkFailed(e.toString());
  }
}
