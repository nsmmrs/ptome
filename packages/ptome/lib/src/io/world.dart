/// What a conversion sees of the process around it, where a zone sets it
/// otherwise: the environment variables and the local time zone. A test
/// can't change the process's own from inside it (the VM reads the time
/// zone from the system), so it runs the code under test in a zone that
/// gives them ([withWorld]); outside one, they are the process's.
library;

import 'dart:async';

import 'package:meta/meta.dart';

final Object _key = Object();

typedef _World = ({Map<String, String>? environment, Duration? utcOffset});

/// Runs [body] with [environment] as the process's environment variables
/// and [utcOffset] as the local time zone's offset from UTC, each where
/// given.
@visibleForTesting
R withWorld<R>(
  R Function() body, {
  Map<String, String>? environment,
  Duration? utcOffset,
}) => runZoned(
  body,
  zoneValues: {_key: (environment: environment, utcOffset: utcOffset)},
);

/// The environment variables the current zone gives, if it gives any.
Map<String, String>? get environmentOfZone =>
    (Zone.current[_key] as _World?)?.environment;

/// [time]'s offset from UTC: none for a UTC time; for a local one, the
/// local time zone's.
Duration utcOffsetOf(DateTime time) => time.isUtc
    ? Duration.zero
    : (Zone.current[_key] as _World?)?.utcOffset ?? time.timeZoneOffset;

/// [time] as a clock of its zone shows it ([utcOffsetOf]), in the fields
/// of a UTC time.
DateTime wallClock(DateTime time) =>
    time.isUtc ? time : time.toUtc().add(utcOffsetOf(time));
