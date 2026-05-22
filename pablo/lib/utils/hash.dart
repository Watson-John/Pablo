// djb2 hash from pablo3-foundation.jsx. Drives deterministic EXIF/tag/people
// generation so mock photos look stable across rebuilds.

int pabloHash(String s) {
  int h = 5381;
  for (int i = 0; i < s.length; i++) {
    h = ((h << 5) + h) ^ s.codeUnitAt(i);
    // Force a 32-bit-ish range so it stays positive after the XOR
    h = h & 0xFFFFFFFF;
  }
  return h.abs();
}
