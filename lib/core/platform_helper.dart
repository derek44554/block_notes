import 'dart:io';

import 'package:flutter/foundation.dart';

class PlatformHelper {
  const PlatformHelper._();

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
}
