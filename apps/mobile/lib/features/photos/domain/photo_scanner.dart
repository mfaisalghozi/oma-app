/// Result of the on-device check of one picked photo.
sealed class PhotoVerdict {
  const PhotoVerdict();
}

/// Safe to upload.
final class PhotoAllowed extends PhotoVerdict {
  const PhotoAllowed();
}

/// Blocked on the device and never uploaded. M09 shows "Not approved"
/// with Replace.
final class PhotoRejected extends PhotoVerdict {
  const PhotoRejected(this.reason);

  final PhotoRejectReason reason;
}

enum PhotoRejectReason { nudity, explicitNudity }

/// Checks a photo on the device before it is uploaded (decided 2026-11-03).
///
/// Fails closed: if the model can't be fetched or the scan errors, it throws
/// a `DeviceFailure` and the photo is not uploaded; M09 offers Try again.
///
/// This is one signal, not the only gate. A modified client can skip it, so
/// the backend moderation queue still has to look at every photo.
abstract interface class PhotoScanner {
  /// Downloads and verifies the model if needed. Safe to call repeatedly;
  /// M09 calls it on open so the first scan is fast.
  Future<void> prepare();

  Future<PhotoVerdict> scan(String filePath);
}
