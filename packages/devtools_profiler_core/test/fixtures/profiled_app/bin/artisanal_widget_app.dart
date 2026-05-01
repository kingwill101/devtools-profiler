import 'package:artisanal/tui.dart' as tui;
import 'package:artisanal_widgets/widgets.dart' as w;

Future<void> main() async {
  final app = tui.WidgetApp(ProfilerWidgetApp());
  await tui.runProgram(
    app,
    options: const tui.ProgramOptions(
      altScreen: true,
      mouseMode: tui.MouseMode.allMotion,
    ),
  );
}

class ProfilerWidgetApp extends w.StatefulWidget {
  ProfilerWidgetApp({super.key});

  @override
  w.State createState() => _ProfilerWidgetAppState();
}

class _ProfilerWidgetAppState extends w.State<ProfilerWidgetApp> {
  final w.WidgetScrollController _scrollController = w.WidgetScrollController();
  var _count = 0;

  @override
  w.Widget build(w.BuildContext context) {
    _burnCpu();
    return w.Container(
      padding: const w.EdgeInsets.all(1),
      color: widget.theme.background,
      child: w.Scrollbar(
        controller: _scrollController,
        child: w.ScrollView(
          controller: _scrollController,
          handleKeys: true,
          child: w.Column(
            gap: 1,
            children: [
              w.Text('Profiler TUI Fixture', style: widget.theme.titleLarge),
              w.Text('Count: $_count', style: widget.theme.titleMedium),
              w.Text(
                'Adapted from artisanal_widgets/example/widget-app.',
                style: widget.theme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  tui.Cmd? handleInit() {
    return tui.ParallelCmd([
      tui.every(const Duration(milliseconds: 50), (time) => tui.TickMsg(time)),
      tui.Cmd.delayed(
        const Duration(milliseconds: 2500),
        () => const tui.QuitMsg(),
      ),
    ]);
  }

  @override
  tui.Cmd? handleUpdate(tui.Msg msg) {
    if (msg is tui.KeyMsg && msg.key.char == 'q') {
      return tui.Cmd.quit();
    }
    if (msg is tui.TickMsg) {
      setState(() => _count++);
    }
    return null;
  }
}

void _burnCpu() {
  var state = 1;
  for (var i = 0; i < 2_000_000; i++) {
    state = ((state * 1664525) + i) & 0x7fffffff;
  }
  if (state == -1) {
    throw StateError('unreachable');
  }
}
