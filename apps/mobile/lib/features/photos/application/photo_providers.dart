import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/photo_adapters.dart';
import '../domain/photo_upload.dart';

final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) => ApiPhotoRepository(ref.watch(apiClientProvider)),
);

final photoStorageProvider = Provider<PhotoStorage>(
  (ref) => SupabasePhotoStorage(),
);

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => ImagePickerPhotoPicker(),
);

final photoCompressorProvider = Provider<PhotoCompressor>(
  (ref) => NativePhotoCompressor(),
);

final photoSignedUrlsProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(photoRepositoryProvider).signedUrls(),
);
