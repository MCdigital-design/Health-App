import 'package:flutter/material.dart';

import '../storage/local_db.dart';

ChartSignal? chartSignalFromName(String? name) {
  switch (name?.toLowerCase().replaceAll(' ', '').replaceAll('_', '')) {
    case 'hr':
    case 'heart':
    case 'heartrate':
      return ChartSignal.hr;
    case 'ppg':
      return ChartSignal.ppg;
    case 'ppi':
    case 'rr':
      return ChartSignal.ppi;
    case 'acc':
    case 'accel':
    case 'accelerometer':
      return ChartSignal.acc;
    case 'gyro':
    case 'gyroscope':
      return ChartSignal.gyro;
    case 'mag':
    case 'magnetometer':
      return ChartSignal.mag;
    default:
      return null;
  }
}

({Color color, String? unit}) signalStyle(ChartSignal signal) {
  return switch (signal) {
    ChartSignal.hr => (color: Colors.redAccent, unit: 'bpm'),
    ChartSignal.ppg => (color: Colors.blueAccent, unit: null),
    ChartSignal.ppi => (color: Colors.lightGreenAccent, unit: 'ms'),
    ChartSignal.acc => (color: Colors.tealAccent, unit: 'mg'),
    ChartSignal.gyro => (color: Colors.amberAccent, unit: null),
    ChartSignal.mag => (color: Colors.purpleAccent, unit: null),
  };
}
