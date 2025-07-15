import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload image to Firebase Storage
  Future<String> uploadImageToStorage(
      String childName, Uint8List file, bool isPost,
      {String contentType = 'image/jpeg'}) async {
    try {
      // 1. Create a reference in Firebase Storage
      Reference ref =
          _storage.ref().child(childName).child(_auth.currentUser!.uid);
      if (isPost) {
        String id = const Uuid().v1();
        ref = ref.child(id);
      }

      // 2. Set metadata dynamically based on contentType
      final metadata = SettableMetadata(contentType: contentType);

      // 3. Upload the file with metadata
      UploadTask uploadTask = ref.putData(file, metadata);

      // 4. Await the completion of the upload
      TaskSnapshot snapshot = await uploadTask;

// 5. Wait for the Extension to finish resizing
      await Future.delayed(const Duration(milliseconds: 3300));

// 6. Instead of the original, fetch the 200×200 thumbnail URL
      final parentRef = snapshot.ref.parent!;
      final thumbRef = parentRef.child('${snapshot.ref.name}_1024x1024');
      String downloadUrl = await thumbRef.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // Delete an image from Firebase Storage given its download URL.
  Future<void> deleteImage(String imageUrl) async {
    try {
      // Validate the URL format
      if (!imageUrl.startsWith('gs://') &&
          !imageUrl.contains('firebasestorage.googleapis.com')) {
        throw Exception('Invalid Firebase Storage URL: $imageUrl');
      }

      Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      rethrow; // Propagate the error to the caller
    }
  }
}
