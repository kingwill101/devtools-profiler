import 'package:devtools_region_profiler/devtools_region_profiler.dart';

Future<void> main() async {
  final handle = startProfileRegionSync('immediate-stop');
  try {
    await handle.stop();
    print('stopped');
  } catch (_) {
    print('rejected');
  }
}
