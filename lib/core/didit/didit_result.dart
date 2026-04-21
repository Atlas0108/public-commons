/// Outcome of attempting to open the Didit native verification flow.
sealed class DiditResult {
  const DiditResult();
}

/// User finished the SDK flow (check status; final truth comes from your v3 webhook).
final class DiditSdkCompleted extends DiditResult {
  const DiditSdkCompleted({required this.statusLabel, this.sessionId});

  final String statusLabel;
  final String? sessionId;
}

final class DiditSdkCancelled extends DiditResult {
  const DiditSdkCancelled();
}

final class DiditSdkFailed extends DiditResult {
  const DiditSdkFailed(this.message);

  final String message;
}

/// Web, desktop, or unsupported device — use hosted URL / backend flow instead.
final class DiditUnsupported extends DiditResult {
  const DiditUnsupported(this.reason);

  final String reason;
}
