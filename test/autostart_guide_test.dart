import 'package:flutter_test/flutter_test.dart';
import 'package:readalarm/screens/onboarding/oem_autostart_screen.dart';

void main() {
  test('each phone maker gets its own auto-start guide', () {
    const expected = {
      'TECNO MOBILE LIMITED': 'Tecno / Infinix / itel',
      'INFINIX': 'Tecno / Infinix / itel',
      'Xiaomi': 'Xiaomi / Redmi / Poco',
      'samsung': 'Samsung',
      'OPPO': 'Oppo / Realme / OnePlus',
      'realme': 'Oppo / Realme / OnePlus',
      'OnePlus': 'Oppo / Realme / OnePlus',
      'vivo': 'Vivo',
      'HUAWEI': 'Huawei / Honor',
      'HONOR': 'Huawei / Honor',
      'Google': 'Other',
    };
    for (final e in expected.entries) {
      expect(OemAutostartScreen.brandFor(e.key), e.value, reason: e.key);
    }
  });
}
