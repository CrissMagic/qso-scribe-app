import '../domain/app_models.dart';

String toAdifRecord(QsoDraft qso) {
  final dateTime = qso.dateTime.value;
  return [
    _field('CALL', qso.callsign.value),
    if (dateTime != null) _field('QSO_DATE', _date(dateTime)),
    if (dateTime != null) _field('TIME_ON', _time(dateTime)),
    _field('BAND', qso.band.value),
    _field('FREQ', qso.frequency.value),
    _field('MODE', qso.mode.value),
    _field('RST_SENT', qso.sentRst.value),
    _field('RST_RCVD', qso.receivedRst.value),
    if (qso.name?.value.isNotEmpty ?? false) _field('NAME', qso.name!.value),
    if (qso.qth?.value.isNotEmpty ?? false) _field('QTH', qso.qth!.value),
    if (qso.notes?.value.isNotEmpty ?? false)
      _field('COMMENT', qso.notes!.value),
    if (qso.rig?.value.isNotEmpty ?? false) _field('MY_RIG', qso.rig!.value),
    '<EOR>',
  ].join(' ');
}

String _field(String name, String value) => '<$name:${value.length}>$value';

String _date(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _time(DateTime value) {
  final utc = value.toUtc();
  return '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}';
}
