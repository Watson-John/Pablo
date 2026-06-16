// Mock data — verbatim port of PEOPLE / FOLDERS / ALBUMS / TIMELINE_YEARS /
// UNNAMED_FACES / MAP_LOCATIONS from pablo3-foundation.jsx + pablo3-map.jsx.

import '../models.dart';

const List<Person> kPeople = [
  Person(id: 'p1', name: 'Sarah Chen', count: 308, lastDate: 'Dec 2024', hue: 15),
  Person(id: 'p2', name: 'James Park', count: 121, lastDate: 'Nov 2024', hue: 200),
  Person(id: 'p3', name: 'Emma', count: 111, lastDate: 'Oct 2024', hue: 340),
  Person(id: 'p4', name: 'Dad', count: 94, lastDate: 'Dec 2024', hue: 30),
  Person(id: 'p5', name: 'Mom', count: 67, lastDate: 'Aug 2024', hue: 0),
  Person(id: 'p6', name: 'Tom Wheeler', count: 18, lastDate: 'Jun 2024', hue: 50),
  Person(id: 'p7', name: 'Aunt Lisa', count: 42, lastDate: 'Jul 2024', hue: 320),
  Person(id: 'p8', name: 'Uncle Rob', count: 29, lastDate: 'Mar 2024', hue: 180),
  Person(id: 'p9', name: 'Mia', count: 35, lastDate: 'Sep 2024', hue: 280),
];

const List<FolderNode> kFolders = [
  FolderNode(id: 'fc', name: 'Christmas Pictures', children: [
    FolderNode(id: 'fc24', name: 'Christmas 2024', count: 34, date: 'Dec 2024', path: 'Photos / Christmas / 2024'),
    FolderNode(id: 'fc23', name: 'Christmas 2023', count: 28, date: 'Dec 2023', path: 'Photos / Christmas / 2023'),
    FolderNode(id: 'fc22', name: 'Christmas 2022', count: 41, date: 'Dec 2022', path: 'Photos / Christmas / 2022'),
    FolderNode(id: 'fc-edit', name: 'To Edit', count: 12, date: 'Mixed', path: 'Photos / Christmas / To Edit'),
  ]),
  FolderNode(id: 'fgrad', name: 'Graduation', children: [
    FolderNode(id: 'fg-emma', name: "Emma's Graduation 2024", count: 67, date: 'Jun 2024', path: 'Photos / Graduation / Emma'),
    FolderNode(id: 'fg-james', name: 'James Grad 2022', count: 43, date: 'May 2022', path: 'Photos / Graduation / James'),
    FolderNode(id: 'fg-raw', name: 'RAW Files', count: 89, date: '2022–2024', path: 'Photos / Graduation / RAW'),
  ]),
  FolderNode(id: 'fvac', name: 'Vacations', children: [
    FolderNode(id: 'fv-or', name: 'Oregon Coast 2024', count: 29, date: 'Aug 2024', path: 'Photos / Vacations / Oregon'),
    FolderNode(id: 'fv-fl', name: 'Florida Trip 2023', count: 56, date: 'Jul 2023', path: 'Photos / Vacations / Florida'),
    FolderNode(id: 'fv-np', name: 'National Parks 2022', count: 88, date: 'Sep 2022', path: 'Photos / Vacations / NatParks'),
  ]),
  FolderNode(id: 'fsch', name: 'School Events', children: [
    FolderNode(id: 'fs-play', name: 'Spring Play 2024', count: 31, date: 'Apr 2024', path: 'Photos / School / Play'),
    FolderNode(id: 'fs-soc', name: 'Soccer Games', count: 48, date: '2023–2024', path: 'Photos / School / Soccer'),
    FolderNode(id: 'fs-misc', name: 'Misc School', count: 22, date: '2022–2024', path: 'Photos / School / Misc'),
  ]),
  FolderNode(id: 'fport', name: 'Family Portraits', children: [
    FolderNode(id: 'fp-24', name: '2024 Session', count: 18, date: 'Oct 2024', path: 'Photos / Portraits / 2024'),
    FolderNode(id: 'fp-22', name: '2022 Session', count: 24, date: 'Mar 2022', path: 'Photos / Portraits / 2022'),
    FolderNode(id: 'fp-print', name: 'To Print', count: 8, date: '2024', path: 'Photos / Portraits / Print'),
  ]),
  FolderNode(id: 'fdl', name: 'Downloads & Imports', children: [
    FolderNode(id: 'fd-fb', name: 'Facebook Exports', count: 17, date: '2022', path: 'Photos / Downloads / Facebook'),
    FolderNode(id: 'fd-phone', name: 'Phone Backups', count: 234, date: '2022–2024', path: 'Photos / Downloads / Phone'),
    FolderNode(id: 'fd-scan', name: 'Scanned Old Photos', count: 148, date: '2022', path: 'Photos / Downloads / Scans'),
  ]),
  FolderNode(id: 'fbday', name: 'Birthdays', children: [
    FolderNode(id: 'fb-kids', name: 'Kids Birthdays', count: 52, date: '2020–2024', path: 'Photos / Birthdays / Kids'),
    FolderNode(id: 'fb-adult', name: 'Adult Parties', count: 19, date: '2022–2024', path: 'Photos / Birthdays / Adults'),
  ]),
];

const List<Album> kAlbums = [
  Album(id: 'a1', name: 'Christmas 2024', count: 24, created: 'Dec 2024'),
  Album(id: 'a2', name: 'Oregon Coast Trip', count: 45, created: 'Aug 2024'),
  Album(id: 'a3', name: 'Family Portraits', count: 18, created: 'Mar 2024'),
  Album(id: 'a4', name: 'Kids School Events', count: 31, created: 'Sep 2024'),
  Album(id: 'a5', name: 'Vacation 2023', count: 56, created: 'Jul 2023'),
];

const List<TimelineNode> kTimelineYears = [
  TimelineNode(id: 'ty24', label: '2024', children: [
    TimelineNode(id: 'tm2412', label: 'December 2024', count: 34, children: [
      TimelineNode(id: 'td241225', label: 'December 25, 2024', count: 22),
      TimelineNode(id: 'td241224', label: 'December 24, 2024', count: 12),
    ]),
    TimelineNode(id: 'tm2410', label: 'October 2024', count: 18, children: [
      TimelineNode(id: 'td241015', label: 'October 15, 2024', count: 8),
      TimelineNode(id: 'td241020', label: 'October 20, 2024', count: 10),
    ]),
    TimelineNode(id: 'tm2408', label: 'August 2024', count: 29, children: [
      TimelineNode(id: 'td240815', label: 'August 15, 2024', count: 14),
      TimelineNode(id: 'td240816', label: 'August 16, 2024', count: 15),
    ]),
    TimelineNode(id: 'tm2406', label: 'June 2024', count: 67, children: [
      TimelineNode(id: 'td240601', label: 'June 1, 2024', count: 67),
    ]),
    TimelineNode(id: 'tm2404', label: 'April 2024', count: 31, children: [
      TimelineNode(id: 'td240412', label: 'April 12, 2024', count: 31),
    ]),
  ]),
  TimelineNode(id: 'ty23', label: '2023', children: [
    TimelineNode(id: 'tm2312', label: 'December 2023', count: 28, children: [
      TimelineNode(id: 'td231225', label: 'December 25, 2023', count: 18),
      TimelineNode(id: 'td231231', label: 'December 31, 2023', count: 10),
    ]),
    TimelineNode(id: 'tm2307', label: 'July 2023', count: 56, children: [
      TimelineNode(id: 'td230710', label: 'July 10, 2023', count: 18),
      TimelineNode(id: 'td230712', label: 'July 12, 2023', count: 22),
      TimelineNode(id: 'td230715', label: 'July 15, 2023', count: 16),
    ]),
    TimelineNode(id: 'tm2305', label: 'May 2023', count: 43, children: [
      TimelineNode(id: 'td230505', label: 'May 5, 2023', count: 15),
      TimelineNode(id: 'td230518', label: 'May 18, 2023', count: 28),
    ]),
  ]),
  TimelineNode(id: 'ty22', label: '2022', children: [
    TimelineNode(id: 'tm2212', label: 'December 2022', count: 41, children: [
      TimelineNode(id: 'td221225', label: 'December 25, 2022', count: 41),
    ]),
    TimelineNode(id: 'tm2209', label: 'September 2022', count: 88, children: [
      TimelineNode(id: 'td220905', label: 'September 5, 2022', count: 31),
      TimelineNode(id: 'td220907', label: 'September 7, 2022', count: 57),
    ]),
    TimelineNode(id: 'tm2205', label: 'May 2022', count: 43, children: [
      TimelineNode(id: 'td220514', label: 'May 14, 2022', count: 43),
    ]),
    TimelineNode(id: 'tm2203', label: 'March 2022', count: 24, children: [
      TimelineNode(id: 'td220312', label: 'March 12, 2022', count: 24),
    ]),
  ]),
];

/// Flat list of all timeline months/days (used for SectionScrollView).
List<TimelineNode> get kTimelineMonths {
  final out = <TimelineNode>[];
  for (final y in kTimelineYears) {
    for (final m in y.children) {
      out.add(m);
      for (final d in m.children) {
        out.add(d);
      }
    }
  }
  return out;
}

final List<UnnamedFace> kUnnamedFaces = List.generate(18, (i) {
  final hue = (i * 23 + 10) % 360;
  const counts = [5, 12, 3, 8, 21, 4, 9, 2, 15, 7, 11, 6, 3, 18, 4, 9, 2, 7];
  return UnnamedFace(id: 'uf-$i', hue: hue, count: counts[i]);
});

const List<MapLocation> kMapLocations = [
  MapLocation(id: 'seattle', name: 'Seattle, WA', cx: 83, cy: 45, count: 75),
  MapLocation(id: 'portland', name: 'Portland, OR', cx: 78, cy: 100, count: 90),
  MapLocation(id: 'sandiego', name: 'San Diego, CA', cx: 141, cy: 307, count: 45),
  MapLocation(id: 'yellowstone', name: 'Yellowstone, WY', cx: 224, cy: 107, count: 60),
  MapLocation(id: 'newyork', name: 'New York, NY', cx: 664, cy: 186, count: 180),
  MapLocation(id: 'miami', name: 'Miami Beach, FL', cx: 592, cy: 415, count: 120),
];

const String kUsaPath =
    'M 54,42 L 56,80 L 57,155 L 86,215 L 128,282 L 141,307 '
    'L 243,327 L 273,319 L 303,355 '
    'L 383,418 L 383,386 L 415,361 L 427,351 '
    'L 478,366 L 485,343 L 497,337 '
    'L 506,343 L 524,347 L 534,355 '
    'L 563,385 L 570,406 L 580,429 '
    'L 571,442 L 592,415 L 586,374 L 573,344 '
    'L 581,316 L 647,257 L 629,200 L 664,186 L 711,153 L 744,106 '
    'L 749,101 L 678,97 L 557,148 L 447,67 '
    'L 410,30 L 303,30 L 159,30 L 147,30 Z';

const List<String> kAdvSearchCameras = [
  'Any', 'Canon EOS R5', 'Sony A7IV', 'Nikon Z6', 'iPhone 15 Pro',
  'Samsung S24', 'Google Pixel 8', 'Fujifilm X-T5',
];

const List<String> kAdvSearchFileTypes = [
  'Any', 'JPEG', 'RAW', 'PNG', 'HEIC', 'MP4', 'MOV',
];

const List<String> kAdvSearchMonths = [
  'Any', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];
