/// Exception thrown by the IWAD runtime wrapper.
final class IwadRuntimeException implements Exception {
  /// Creates an exception with a human-readable [message].
  const IwadRuntimeException(this.message);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'IwadRuntimeException: $message';
}
