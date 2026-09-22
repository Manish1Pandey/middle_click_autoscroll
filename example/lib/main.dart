import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:middle_click_autoscroll/middle_click_autoscroll.dart';

import 'demo_state.dart';
import 'fixed_grid.dart';

void main() => runApp(const AutoscrollDemoApp());

/// Demo app for `autoscroll`.
class AutoscrollDemoApp extends StatelessWidget {
  /// Creates the demo app.
  const AutoscrollDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Middle-click autoscroll example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const DemoHome(),
    );
  }
}

enum _CurveChoice { chrome, linear, gentle }

enum _IndicatorChoice { classic, custom, hidden }

/// Settings panel plus one tab per scrollable layout.
class DemoHome extends StatefulWidget {
  /// Creates the home page.
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  bool _enabled = true;
  // `?mode=toggle|hold|auto` in the URL (web) preselects the mode.
  AutoscrollMode _mode = AutoscrollMode.values.firstWhere(
    (AutoscrollMode m) => m.name == Uri.base.queryParameters['mode'],
    orElse: () => AutoscrollMode.auto,
  );
  bool _active = false;
  final ScrollController _verticalController = ScrollController();
  double _deadZone = 15;
  double _maxSpeed = 6000;
  _CurveChoice _curve = _CurveChoice.chrome;
  _IndicatorChoice _indicator = _IndicatorChoice.classic;
  bool _preventBrowserDefaults = true;
  String _status = 'Idle. Press the mouse wheel over a list.';
  final ScrollController _controllerTabController = ScrollController();

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_publish);
    _publish();
  }

  void _publish() {
    publishDemoState(
      jsonEncode(<String, Object?>{
        'vertical': _verticalController.hasClients
            ? _verticalController.offset
            : 0.0,
        'active': _active,
        'mode': _mode.name,
        'status': _status,
      }),
    );
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _controllerTabController.dispose();
    super.dispose();
  }

  AutoscrollSpeedCurve get _speedCurve => switch (_curve) {
    _CurveChoice.chrome => AutoscrollSpeedCurve.chrome,
    _CurveChoice.linear => const LinearAutoscrollSpeedCurve(
      pixelsPerSecondPerPixel: 8,
    ),
    _CurveChoice.gentle => const PowerAutoscrollSpeedCurve(
      multiplier: 0.2,
      exponent: 1.5,
    ),
  };

  Widget _customIndicator(BuildContext context, AutoscrollDetails d) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer.withValues(alpha: 0.92),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '${d.velocity.distance.round()}\npx/s',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer),
      ),
    );
  }

  /// Wraps [child] with the autoscroll widget configured by the panel.
  Widget _autoscroll({required Widget child, ScrollController? controller}) {
    return MiddleClickAutoscroll(
      enabled: _enabled,
      mode: _mode,
      controller: controller,
      deadZoneRadius: _deadZone,
      maxSpeed: _maxSpeed,
      speedCurve: _speedCurve,
      showIndicator: _indicator != _IndicatorChoice.hidden,
      indicatorBuilder: _indicator == _IndicatorChoice.custom
          ? _customIndicator
          : defaultAutoscrollIndicatorBuilder,
      preventBrowserDefaults: _preventBrowserDefaults,
      onAutoscrollStart: (AutoscrollDetails d) => setState(() {
        final String axes = [
          if (d.canScrollVertically) 'vertical',
          if (d.canScrollHorizontally) 'horizontal',
        ].join(' + ');
        _status = 'Autoscrolling ($axes) from ${_fmt(d.anchor)}';
        _active = true;
        _publish();
      }),
      onAutoscrollEnd: () => setState(() {
        _status = 'Stopped.';
        _active = false;
        _publish();
      }),
      child: child,
    );
  }

  static String _fmt(Offset o) =>
      '(${o.dx.toStringAsFixed(0)}, ${o.dy.toStringAsFixed(0)})';

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 760;
    final Widget panel = _SettingsPanel(
      enabled: _enabled,
      mode: _mode,
      deadZone: _deadZone,
      maxSpeed: _maxSpeed,
      curve: _curve,
      indicator: _indicator,
      preventBrowserDefaults: _preventBrowserDefaults,
      status: _status,
      onEnabled: (bool v) => setState(() => _enabled = v),
      onMode: (AutoscrollMode v) => setState(() {
        _mode = v;
        _publish();
      }),
      onDeadZone: (double v) => setState(() => _deadZone = v),
      onMaxSpeed: (double v) => setState(() => _maxSpeed = v),
      onCurve: (_CurveChoice v) => setState(() => _curve = v),
      onIndicator: (_IndicatorChoice v) => setState(() => _indicator = v),
      onPreventBrowserDefaults: (bool v) =>
          setState(() => _preventBrowserDefaults = v),
    );
    final Widget tabs = TabBarView(
      children: <Widget>[
        _autoscroll(child: _VerticalTab(controller: _verticalController)),
        _autoscroll(child: const _HorizontalTab()),
        _autoscroll(child: const _GridTab()),
        _autoscroll(child: const _NestedTab()),
        _autoscroll(
          controller: _controllerTabController,
          child: _ControllerTab(controller: _controllerTabController),
        ),
      ],
    );
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Middle-click autoscroll'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Vertical'),
              Tab(text: 'Horizontal'),
              Tab(text: '2D grid'),
              Tab(text: 'Nested'),
              Tab(text: 'Controller'),
            ],
          ),
        ),
        endDrawer: wide ? null : Drawer(child: panel),
        body: wide
            ? Row(
                children: <Widget>[
                  SizedBox(width: 300, child: panel),
                  const VerticalDivider(width: 1),
                  Expanded(child: tabs),
                ],
              )
            : tabs,
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.enabled,
    required this.mode,
    required this.deadZone,
    required this.maxSpeed,
    required this.curve,
    required this.indicator,
    required this.preventBrowserDefaults,
    required this.status,
    required this.onEnabled,
    required this.onMode,
    required this.onDeadZone,
    required this.onMaxSpeed,
    required this.onCurve,
    required this.onIndicator,
    required this.onPreventBrowserDefaults,
  });

  final bool enabled;
  final AutoscrollMode mode;
  final double deadZone;
  final double maxSpeed;
  final _CurveChoice curve;
  final _IndicatorChoice indicator;
  final bool preventBrowserDefaults;
  final String status;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<AutoscrollMode> onMode;
  final ValueChanged<double> onDeadZone;
  final ValueChanged<double> onMaxSpeed;
  final ValueChanged<_CurveChoice> onCurve;
  final ValueChanged<_IndicatorChoice> onIndicator;
  final ValueChanged<bool> onPreventBrowserDefaults;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(status, style: text.bodyMedium),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Press the wheel, move away from the anchor. Click, press Escape, '
          'switch windows or leave the window to stop.',
          style: text.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: enabled,
          onChanged: onEnabled,
        ),
        Text('Mode', style: text.titleSmall),
        const SizedBox(height: 4),
        SegmentedButton<AutoscrollMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<AutoscrollMode>>[
            ButtonSegment<AutoscrollMode>(
              value: AutoscrollMode.auto,
              label: Text('Auto'),
            ),
            ButtonSegment<AutoscrollMode>(
              value: AutoscrollMode.toggle,
              label: Text('Toggle'),
            ),
            ButtonSegment<AutoscrollMode>(
              value: AutoscrollMode.hold,
              label: Text('Hold'),
            ),
          ],
          selected: <AutoscrollMode>{mode},
          onSelectionChanged: (Set<AutoscrollMode> s) => onMode(s.first),
        ),
        const SizedBox(height: 16),
        Text('Dead zone: ${deadZone.round()} px', style: text.titleSmall),
        Slider(value: deadZone, min: 0, max: 60, onChanged: onDeadZone),
        Text('Max speed: ${maxSpeed.round()} px/s', style: text.titleSmall),
        Slider(
          value: maxSpeed,
          min: 200,
          max: 12000,
          divisions: 59,
          onChanged: onMaxSpeed,
        ),
        Text('Speed curve', style: text.titleSmall),
        RadioGroup<_CurveChoice>(
          groupValue: curve,
          onChanged: (_CurveChoice? v) => onCurve(v!),
          child: const Column(
            children: <Widget>[
              RadioListTile<_CurveChoice>(
                contentPadding: EdgeInsets.zero,
                value: _CurveChoice.chrome,
                title: Text('Chrome-like (0.011·d^2.2)'),
              ),
              RadioListTile<_CurveChoice>(
                contentPadding: EdgeInsets.zero,
                value: _CurveChoice.linear,
                title: Text('Linear (8 px/s per px)'),
              ),
              RadioListTile<_CurveChoice>(
                contentPadding: EdgeInsets.zero,
                value: _CurveChoice.gentle,
                title: Text('Gentle power (0.2·d^1.5)'),
              ),
            ],
          ),
        ),
        Text('Indicator', style: text.titleSmall),
        const SizedBox(height: 4),
        SegmentedButton<_IndicatorChoice>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<_IndicatorChoice>>[
            ButtonSegment<_IndicatorChoice>(
              value: _IndicatorChoice.classic,
              label: Text('Classic'),
            ),
            ButtonSegment<_IndicatorChoice>(
              value: _IndicatorChoice.custom,
              label: Text('Custom'),
            ),
            ButtonSegment<_IndicatorChoice>(
              value: _IndicatorChoice.hidden,
              label: Text('None'),
            ),
          ],
          selected: <_IndicatorChoice>{indicator},
          onSelectionChanged: (Set<_IndicatorChoice> s) => onIndicator(s.first),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Block browser middle-click (web)'),
          subtitle: const Text(
            'Native autoscroll and Linux paste. Try middle-clicking the '
            'field below with text in your primary selection.',
          ),
          value: preventBrowserDefaults,
          onChanged: onPreventBrowserDefaults,
        ),
        const TextField(
          decoration: InputDecoration(
            labelText: 'Paste target',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _VerticalTab extends StatelessWidget {
  const _VerticalTab({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      itemCount: 5000,
      itemBuilder: (BuildContext context, int i) => ListTile(
        leading: CircleAvatar(child: Text('${i % 100}')),
        title: Text('Row $i'),
        subtitle: const Text('Middle-click, then move the mouse up or down.'),
      ),
    );
  }
}

class _HorizontalTab extends StatelessWidget {
  const _HorizontalTab();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 2000,
      itemExtent: 160,
      itemBuilder: (BuildContext context, int i) => Card(
        margin: const EdgeInsets.all(8),
        color: Colors.primaries[i % Colors.primaries.length].shade100,
        child: Center(
          child: Text('Column $i', style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}

class _GridTab extends StatelessWidget {
  const _GridTab();

  @override
  Widget build(BuildContext context) {
    return FixedGrid(
      cellSize: 110,
      delegate: TwoDimensionalChildBuilderDelegate(
        maxXIndex: 199,
        maxYIndex: 499,
        builder: (BuildContext context, ChildVicinity v) => Container(
          margin: const EdgeInsets.all(2),
          color: Color.lerp(
            Colors.indigo.shade50,
            Colors.teal.shade200,
            ((v.xIndex + v.yIndex) % 20) / 20,
          ),
          alignment: Alignment.center,
          child: Text('${v.xIndex}, ${v.yIndex}'),
        ),
      ),
    );
  }
}

class _NestedTab extends StatelessWidget {
  const _NestedTab();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 60,
      itemBuilder: (BuildContext context, int row) {
        if (row % 5 == 2) {
          return SizedBox(
            height: 220,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: ListView.builder(
                itemCount: 30,
                itemBuilder: (BuildContext context, int i) => ListTile(
                  dense: true,
                  title: Text('Inner vertical list $row · item $i'),
                  subtitle: const Text(
                    'Scrolls first; hands off to the page at its end.',
                  ),
                ),
              ),
            ),
          );
        }
        return SizedBox(
          height: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text('Shelf $row (horizontal inside vertical)'),
              ),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 40,
                  itemExtent: 120,
                  itemBuilder: (BuildContext context, int i) => Card(
                    margin: const EdgeInsets.all(6),
                    color: Colors
                        .accents[(row + i) % Colors.accents.length]
                        .shade100,
                    child: Center(child: Text('$row · $i')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControllerTab extends StatelessWidget {
  const _ControllerTab({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 220,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Controller mode: MiddleClickAutoscroll is given the list\'s '
            'ScrollController, so a middle click anywhere here - even on '
            'this non-scrolling panel - drives the list on the right.',
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            itemCount: 3000,
            itemBuilder: (BuildContext context, int i) =>
                ListTile(title: Text('Controlled item $i')),
          ),
        ),
      ],
    );
  }
}
