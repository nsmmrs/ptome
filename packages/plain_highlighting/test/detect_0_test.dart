// Auto-detection, part 1 of 2 (test/detect_cases.dart).
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'detect_cases.dart';

void main() => detectTests(part: 0, parts: 2);
