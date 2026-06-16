// hue.dart — deterministic placeholder hue from a stable id.
//
// One definition shared by the face repository (Person/UnnamedFace row hues),
// FaceThumb's gradient fallback, and any avatar tile, so a person's color, its
// cluster-card cover, and the faces inside it never drift apart.

int hueForId(int id) => (id.abs() * 47) % 360;
