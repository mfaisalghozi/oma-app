sealed class PhotoVerdict {
  const PhotoVerdict();
}

final class PhotoAllowed extends PhotoVerdict {
  const PhotoAllowed();
}

final class PhotoRejected extends PhotoVerdict {
  const PhotoRejected(this.reason);

  final PhotoRejectReason reason;
}

enum PhotoRejectReason { nudity, explicitNudity }

/// Fails closed. One signal only: a modified client can skip it, so backend
/// moderation still reviews every photo.
abstract interface class PhotoScanner {
  Future<void> prepare();

  Future<PhotoVerdict> scan(String filePath);
}
