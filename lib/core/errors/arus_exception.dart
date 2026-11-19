/// Typed domain and infrastructure exceptions for Arus.
sealed class ArusException implements Exception {
  const ArusException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ValidationException extends ArusException {
  const ValidationException(super.message);
}

class LedgerImbalanceException extends ArusException {
  const LedgerImbalanceException(super.message);
}

class NegativeAssetBalanceException extends ArusException {
  const NegativeAssetBalanceException({
    required this.walletName,
    required this.currentBalance,
    required this.projectedBalance,
  }) : super(
          'Saldo dompet "$walletName" akan menjadi negatif ($projectedBalance).',
        );

  final String walletName;
  final int currentBalance;
  final int projectedBalance;
}

class GeminiApiException extends ArusException {
  const GeminiApiException(super.message, {this.code = GeminiErrorCode.unknown});

  final GeminiErrorCode code;
}

enum GeminiErrorCode {
  invalidKey,
  permissionDenied,
  modelUnavailable,
  rateLimited,
  quotaExhausted,
  billingRequired,
  noInternet,
  timeout,
  invalidResponse,
  unknown,
}

class BackupException extends ArusException {
  const BackupException(super.message);
}

class DuplicateReceiptException extends ArusException {
  const DuplicateReceiptException(super.message);
}
