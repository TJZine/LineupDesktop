import 'package:flutter/material.dart';

extension type ScheduleWallTime._(DateTime _local) {
  ScheduleWallTime(DateTime instant) : this._(instant.toLocal());

  bool get isMidnight => _local.hour == 0 && _local.minute == 0;

  String get markerLabel {
    final hour = _local.hour % 12;
    return '${hour == 0 ? 12 : hour}:${_local.minute.toString().padLeft(2, '0')}';
  }

  String timeLabel(BuildContext context) => MaterialLocalizations.of(context)
      .formatTimeOfDay(
        TimeOfDay.fromDateTime(_local),
        alwaysUse24HourFormat: false,
      );

  String dateLabel(BuildContext context) =>
      MaterialLocalizations.of(context).formatMediumDate(_local);

  String headerLabel(BuildContext context) =>
      '${dateLabel(context)}  ·  ${timeLabel(context)}';
}
