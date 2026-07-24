/// Base class for failures reported by transfer_manager.
sealed class TransferException implements Exception {
  const TransferException(
    this.message, {
    this.retryable = false,
    this.statusCode,
    this.cause,
  });

  final String message;
  final bool retryable;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class TransferNetworkException extends TransferException {
  const TransferNetworkException(
    super.message, {
    super.retryable = true,
    super.statusCode,
    super.cause,
  });
}

final class TransferServerException extends TransferException {
  const TransferServerException(
    super.message, {
    super.retryable = false,
    super.statusCode,
    super.cause,
  });
}

final class TransferAuthenticationException extends TransferException {
  const TransferAuthenticationException(super.message, {super.cause});
}

final class TransferStorageException extends TransferException {
  const TransferStorageException(
    super.message, {
    super.retryable = false,
    super.cause,
  });
}

final class TransferPermissionException extends TransferException {
  const TransferPermissionException(super.message, {super.cause});
}

final class TransferIntegrityException extends TransferException {
  const TransferIntegrityException(super.message, {super.cause});
}

final class TransferProtocolException extends TransferException {
  const TransferProtocolException(
    super.message, {
    super.retryable = false,
    super.statusCode,
    super.cause,
  });
}

final class TransferSourceMissingException extends TransferException {
  const TransferSourceMissingException(super.message, {super.cause});
}

final class TransferCancelledException extends TransferException {
  const TransferCancelledException() : super('Transfer was cancelled');
}

/// Internal-control signal that custom engines may throw after honoring pause.
final class TransferPausedException implements Exception {
  const TransferPausedException();
}
