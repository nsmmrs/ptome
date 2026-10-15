// Auto-detection, part 2 of 2 (test/detect_cases.dart).
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'detect_cases.dart';

void main() => detectTests(part: 1, parts: 2);
