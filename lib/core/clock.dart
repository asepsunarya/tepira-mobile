import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time. Overridden in tests to make time-based logic
/// deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
