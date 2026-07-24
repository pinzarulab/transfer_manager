import 'models.dart';

final class TransferAuthContext {
  const TransferAuthContext({
    required this.taskId,
    required this.uri,
    required this.type,
    required this.scope,
  });

  final String taskId;
  final Uri uri;
  final TransferType type;
  final String? scope;
}

abstract interface class TransferAuthProvider {
  Future<Map<String, String>> headersFor(TransferAuthContext context);
  Future<Map<String, String>> refreshHeaders(TransferAuthContext context);
}

/// Coalesces concurrent refreshes for the same authentication scope.
final class SingleFlightAuthProvider implements TransferAuthProvider {
  SingleFlightAuthProvider(this.delegate);

  final TransferAuthProvider delegate;
  final Map<String, Future<Map<String, String>>> _refreshes = {};

  @override
  Future<Map<String, String>> headersFor(TransferAuthContext context) =>
      delegate.headersFor(context);

  @override
  Future<Map<String, String>> refreshHeaders(TransferAuthContext context) {
    final key = context.scope ?? '';
    return _refreshes.putIfAbsent(key, () async {
      try {
        return await delegate.refreshHeaders(context);
      } finally {
        _refreshes.remove(key);
      }
    });
  }
}
