// Static UI configuration — not data. Dropdown option lists for the Advanced
// Search modal and the simplified continental-USA outline path used by the Map
// view's chrome. These are constants, not library content, so they live here
// rather than coming from the imported photo library.

const List<String> kAdvSearchCameras = [
  'Any',
  'Canon EOS R5',
  'Sony A7IV',
  'Nikon Z6',
  'iPhone 15 Pro',
  'Samsung S24',
  'Google Pixel 8',
  'Fujifilm X-T5',
];

const List<String> kAdvSearchFileTypes = [
  'Any',
  'JPEG',
  'RAW',
  'PNG',
  'HEIC',
  'MP4',
  'MOV',
];

const List<String> kAdvSearchMonths = [
  'Any',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Simplified continental-USA outline (800×480 viewBox) drawn as the Map view's
/// backdrop. Heat dots are positioned over it from real GPS data when present.
const String kUsaPath = 'M 54,42 L 56,80 L 57,155 L 86,215 L 128,282 L 141,307 '
    'L 243,327 L 273,319 L 303,355 '
    'L 383,418 L 383,386 L 415,361 L 427,351 '
    'L 478,366 L 485,343 L 497,337 '
    'L 506,343 L 524,347 L 534,355 '
    'L 563,385 L 570,406 L 580,429 '
    'L 571,442 L 592,415 L 586,374 L 573,344 '
    'L 581,316 L 647,257 L 629,200 L 664,186 L 711,153 L 744,106 '
    'L 749,101 L 678,97 L 557,148 L 447,67 '
    'L 410,30 L 303,30 L 159,30 L 147,30 Z';
