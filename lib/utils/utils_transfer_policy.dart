class TransferConcurrencyPolicy {
  const TransferConcurrencyPolicy._();

  static const int mobileLimit = 2;
  static const int desktopLimit = 3;

  static int maxConcurrent({required bool isMobile}) =>
      isMobile ? mobileLimit : desktopLimit;
}

enum UploadStorageSelectionStatus {
  selected,
  retryableFailure,
  storageFull,
}

class UploadStorageSelectionPolicy {
  const UploadStorageSelectionPolicy._();

  static const int noStorageErrorCode = 4;

  static UploadStorageSelectionStatus classify(Map<String, dynamic> response) {
    final success = int.tryParse(response['success'].toString()) ?? -1;
    if (success > 0) return UploadStorageSelectionStatus.selected;

    final messageCode = int.tryParse(response['message'].toString());
    if (success == 0 && messageCode == noStorageErrorCode) {
      return UploadStorageSelectionStatus.storageFull;
    }
    return UploadStorageSelectionStatus.retryableFailure;
  }
}

class B2UploadRecoveryPolicy {
  const B2UploadRecoveryPolicy._();

  static const attemptedKey = 'b2_upload_attempted';

  static bool wasAttempted(Map<String, dynamic> partData) =>
      partData[attemptedKey] == true;

  static Map<String, dynamic> markAttempted(Map<String, dynamic> partData) =>
      Map<String, dynamic>.from(partData)..[attemptedKey] = true;

  static String? recoveredFileId(Map<String, dynamic> response) {
    if (response['success'] != 1) return null;
    final data = response['data'];
    if (data is! Map || data['fileId'] is! String) return null;
    final fileId = data['fileId'] as String;
    return fileId.isEmpty ? null : fileId;
  }
}
