/// The astronomy the calendars that follow the sky need: the Sun's and
/// the Moon's apparent ecliptic longitudes, new moons and the moments
/// the Sun reaches a longitude (equinoxes, solstices, solar terms).
///
/// The Sun from ERFA's eraEpv00 (the IAU's SOFA, fitted to DE405), its
/// Sun-to-Earth series in the J2000 ecliptic carried to the ecliptic of
/// date by the IAU 2006 general precession in longitude (IERS Conventions
/// 2010, 5.40); the Moon from eraMoon98 (Meeus' series, mean ecliptic of
/// date); both corrected by the IAU 2000B nutation in longitude
/// (eraNut00b), the Sun for aberration. Times are UT, as days from
/// 1970-01-01, TT from them by ΔT (Espenak and Meeus' expressions, NASA,
/// 2006). The longitudes are good to a few arcseconds: the moments to well
/// within a minute.
library;

import 'dart:math' as math;

import 'package:plain_unicode/src/astronomy.g.dart';

const double _arcsecond = math.pi / 648000;
const double _degree = math.pi / 180;

/// The mean synodic month, in days.
const double synodicMonth = 29.530588853;

/// The mean tropical year, in days.
const double tropicalYear = 365.242189;

/// ΔT (TT − UT), in seconds, at the decimal year [y] (Espenak and Meeus,
/// "Polynomial Expressions for Delta T", NASA, 2006).
double deltaT(double y) {
  double poly(double t, List<double> c) {
    var sum = 0.0;
    for (var i = c.length - 1; i >= 0; i--) {
      sum = sum * t + c[i];
    }
    return sum;
  }

  if (y < 1700) {
    final u = (y - 1820) / 100;
    return -20 + 32 * u * u;
  }
  if (y < 1800) {
    return poly(y - 1700, [8.83, 0.1603, -0.0059285, 0.00013336, -1 / 1174000]);
  }
  if (y < 1860) {
    return poly(y - 1800, [
      13.72,
      -0.332447,
      0.0068612,
      0.0041116,
      -0.00037436,
      0.0000121272,
      -0.0000001699,
      0.000000000875,
    ]);
  }
  if (y < 1900) {
    return poly(y - 1860, [
      7.62,
      0.5737,
      -0.251754,
      0.01680668,
      -0.0004473624,
      1 / 233174,
    ]);
  }
  if (y < 1920) {
    return poly(y - 1900, [-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197]);
  }
  if (y < 1941) return poly(y - 1920, [21.20, 0.84493, -0.076100, 0.0020936]);
  if (y < 1961) return poly(y - 1950, [29.07, 0.407, -1 / 233, 1 / 2547]);
  if (y < 1986) return poly(y - 1975, [45.45, 1.067, -1 / 260, -1 / 718]);
  if (y < 2005) {
    return poly(y - 2000, [
      63.86,
      0.3345,
      -0.060374,
      0.0017275,
      0.000651814,
      0.00002373599,
    ]);
  }
  if (y < 2050) return poly(y - 2000, [62.92, 0.32217, 0.005589]);
  final u = (y - 1820) / 100;
  if (y < 2150) return -20 + 32 * u * u - 0.5628 * (2150 - y);
  return -20 + 32 * u * u;
}

/// Julian centuries of TT from J2000.0 at [days] (UT, from 1970-01-01).
double _centuries(double days) {
  final year = 1970 + days / 365.2425;
  final jd = days + 2440587.5 + deltaT(year) / 86400;
  return (jd - 2451545.0) / 36525;
}

/// [x] in radians, from -π to π.
double _signed(double x) {
  const turn = 2 * math.pi;
  final r = x - turn * (x / turn).floorToDouble();
  return r > math.pi ? r - turn : r;
}

/// The nutation in longitude (radians) at [t] (TT centuries from
/// J2000.0): IAU 2000B's luni-solar terms and its fixed planetary offset.
double _nutation(double t) {
  // (The fundamental arguments, in arcseconds: Simon et al. 1994.)
  double argument(double a, double b) => ((a + b * t) % 1296000) * _arcsecond;
  final l = argument(485868.249036, 1717915923.2178);
  final lp = argument(1287104.79305, 129596581.0481);
  final f = argument(335779.526232, 1739527262.8478);
  final d = argument(1072260.70369, 1602961601.2090);
  final om = argument(450160.398036, -6962890.5431);
  var sum = 0.0;
  for (var i = nutationTerms.length - 1; i >= 0; i--) {
    final x = nutationTerms[i];
    final arg = x[0] * l + x[1] * lp + x[2] * f + x[3] * d + x[4] * om;
    sum += (x[5] + x[6] * t) * math.sin(arg) + x[7] * math.cos(arg);
  }
  // (0.1 microarcseconds; the planetary terms' offset, -0.135 mas.)
  return sum * _arcsecond / 1e7 - 0.135e-3 * _arcsecond;
}

/// The IAU 2006 general precession in longitude (radians) at [t].
double _precession(double t) =>
    (5028.796195 +
        (1.1054348 + (0.00007964 + (-0.000023857 - 0.0000000383 * t) * t) * t) *
            t) *
    t *
    _arcsecond;

/// The Sun's geometric longitude in the mean ecliptic and equinox of date
/// (radians) and its distance (au) at [t].
(double, double) _sun(double t) {
  final years = t * 100;
  final position = [0.0, 0.0, 0.0];
  for (var c = 0; c < 3; c++) {
    var sum = 0.0;
    for (var power = 0; power < 3; power++) {
      final terms = earthSeries[c][power];
      final factor = power == 0 ? 1.0 : (power == 1 ? years : years * years);
      var part = 0.0;
      for (var i = terms.length - 3; i >= 0; i -= 3) {
        part += terms[i] * math.cos(terms[i + 1] + terms[i + 2] * years);
      }
      sum += part * factor;
    }
    position[c] = sum;
  }
  // (The Sun from the Earth: the Earth from the Sun, reversed.)
  final longitude = math.atan2(-position[1], -position[0]) + _precession(t);
  final distance = math.sqrt(
    position[0] * position[0] +
        position[1] * position[1] +
        position[2] * position[2],
  );
  return (longitude, distance);
}

/// The Moon's geometric longitude in the mean ecliptic and equinox of
/// date (radians) at [t]: eraMoon98's series.
double _moon(double t) {
  double angle(List<double> c) =>
      ((c[0] + (c[1] + (c[2] + (c[3] + c[4] * t) * t) * t) * t) % 360) *
      _degree;
  final elp = angle(const [
    218.31665436,
    481267.88123421,
    -0.0015786,
    1 / 538841,
    -1 / 65194000,
  ]);
  final d = angle(const [
    297.8501921,
    445267.1114034,
    -0.0018819,
    1 / 545868,
    1 / 113065000,
  ]);
  final em = angle(const [
    357.5291092,
    35999.0502909,
    -0.0001536,
    1 / 24490000,
    0,
  ]);
  final emp = angle(const [
    134.9633964,
    477198.8675055,
    0.0087414,
    1 / 69699,
    -1 / 14712000,
  ]);
  final f = angle(const [
    93.2720950,
    483202.0175233,
    -0.0036539,
    1 / 3526000,
    1 / 863310000,
  ]);
  final a1 = (119.75 + 131.849 * t) * _degree;
  final a2 = (53.09 + 479264.290 * t) * _degree;
  final e = 1 + (-0.002516 - 0.0000074 * t) * t;
  var sum =
      0.003958 * math.sin(a1) +
      0.001962 * math.sin(elp - f) +
      0.000318 * math.sin(a2);
  for (var i = moonLongitude.length - 1; i >= 0; i--) {
    final (nd, nm, nmp, nf, coefficient, _) = moonLongitude[i];
    final factor = switch (nm.abs()) {
      1 => e,
      2 => e * e,
      _ => 1.0,
    };
    sum +=
        coefficient * factor * math.sin(nd * d + nm * em + nmp * emp + nf * f);
  }
  return elp + sum * _degree;
}

/// The Sun's apparent longitude (radians, 0 to 2π) at [days] (UT, from
/// 1970-01-01).
double sunLongitude(double days) {
  final t = _centuries(days);
  final (longitude, distance) = _sun(t);
  // (Aberration: 20.4898" at 1 au.)
  final apparent = longitude + _nutation(t) - 20.4898 * _arcsecond / distance;
  return apparent % (2 * math.pi);
}

/// The Moon's apparent longitude less the Sun's (radians, -π to π) at
/// [days].
double _elongation(double days) {
  final t = _centuries(days);
  final (sun, distance) = _sun(t);
  // (The nutation shifts both alike.)
  return _signed(_moon(t) - (sun - 20.4898 * _arcsecond / distance));
}

/// The new moon nearest [days] (UT, from 1970-01-01), to within a second.
double newMoonNear(double days) {
  var at = days;
  // (The elongation grows 2π a synodic month; Newton's steps from there.)
  const rate = 2 * math.pi / synodicMonth;
  for (var i = 0; i < 20; i++) {
    final step = _elongation(at) / rate;
    at -= step;
    if (step.abs() < 1e-6) break;
  }
  return at;
}

/// The first new moon after [days] (by more than a second: not the one
/// at [days] again).
double newMoonAfter(double days) {
  const second = 1 / 86400;
  final moon = newMoonNear(days);
  if (moon <= days + second) return newMoonNear(moon + synodicMonth);
  // (The nearest may be the second after: the one before it may be too.)
  final earlier = newMoonNear(moon - synodicMonth);
  return earlier > days + second ? earlier : moon;
}

/// The last new moon at or before [days].
double newMoonAtOrBefore(double days) {
  var moon = newMoonNear(days);
  while (moon > days) {
    moon = newMoonNear(moon - synodicMonth);
  }
  final later = newMoonNear(moon + synodicMonth);
  return later <= days ? later : moon;
}

/// The first moment after [days] the Sun's apparent longitude is
/// [degrees].
double sunReaches(double degrees, double days) {
  final target = degrees * _degree;
  final now = sunLongitude(days);
  final ahead = (target - now) % (2 * math.pi);
  var at = days + ahead / (2 * math.pi) * tropicalYear;
  const rate = 2 * math.pi / tropicalYear;
  for (var i = 0; i < 20; i++) {
    final step = _signed(sunLongitude(at) - target) / rate;
    at -= step;
    if (step.abs() < 1e-6) break;
  }
  return at;
}
