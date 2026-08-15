class TransferConcurrencyPolicy {
  const TransferConcurrencyPolicy._();

  static const int mobileLimit = 2;
  static const int desktopLimit = 3;

  static int maxConcurrent({required bool isMobile}) =>
      isMobile ? mobileLimit : desktopLimit;
}
