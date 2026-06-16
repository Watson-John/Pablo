// asset_id.dart — the single source of truth for deriving a native asset id
// from a photo's stable identity.
//
// The face pipeline links faces to photos by asset id, and the thumbnail
// pipeline requests pixels by asset id. Those must agree, so the gallery
// (PhotoThumb), the ingestion scan (FaceIngestion), and the info-panel People
// tab all route through this one helper instead of hashing inline. In dataset
// mode a photo's id == its file path, so hashing either is equivalent.
//
// Clears the top bit (rather than `.abs()`) so the result is always a
// non-negative int — Dart's hashCode can be negative, and `.abs()` of the most
// negative value stays negative. Real catalog asset ids replace this in M5.

int assetIdFor(String key) => key.hashCode & 0x7FFFFFFFFFFFFFFF;
