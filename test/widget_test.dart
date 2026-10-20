import 'package:flutter_test/flutter_test.dart';
import 'package:novalink_voice/phone.dart';
import 'package:novalink_voice/theme.dart';

void main() {
  test('fmtNumber formats NANP numbers', () {
    expect(fmtNumber('9035550100'), '(903) 555-0100');
    expect(fmtNumber('19035550100'), '(903) 555-0100');
    expect(fmtNumber('1001'), '1001');
  });
  test('fmtDuration', () {
    expect(fmtDuration(65), '01:05');
    expect(fmtDuration(3725), '1:02:05');
  });
  test('emergency numbers go to the native dialer', () {
    for (final n in ['911', '112', '9911', ' 911 ']) { expect(PhoneState.isEmergency(n), true, reason: n); }
    for (final n in ['933', '1911', '9115550100', '411', 'sip:911@x', '']) { expect(PhoneState.isEmergency(n), false, reason: n); }
  });
}
