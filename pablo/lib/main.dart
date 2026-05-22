import 'package:flutter/material.dart';

import 'app/pablo_app.dart';
import 'utils/window_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();
  runApp(const PabloApp());
}
