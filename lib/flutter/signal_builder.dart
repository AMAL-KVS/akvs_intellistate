import 'package:flutter/widgets.dart';
import '../core/signal.dart';
import '../core/dependency_tracker.dart';

/// A widget that reactively rebuilds when signals it depends on change.
///
/// [SignalBuilder] automatically tracks any signals read within its [builder]
/// function using the internal [DependencyTracker].
class SignalBuilder extends StatefulWidget {
  /// The builder function that uses signals to build a widget.
  final Widget Function(BuildContext context) builder;

  /// Optional list of signals to explicitly subscribe to.
  final List<Signal>? signals;

  /// Creates a [SignalBuilder].
  const SignalBuilder({super.key, required this.builder, this.signals});

  @override
  State<SignalBuilder> createState() => _SignalBuilderState();
}

class _SignalBuilderState extends State<SignalBuilder>
    implements SignalObserver {
  final Set<dynamic> _dependencies = {};
  bool _isRebuilding = false;

  @override
  void initState() {
    super.initState();
    // Subscribe to explicit signals if provided.
    if (widget.signals != null) {
      for (final signal in widget.signals!) {
        _subscribe(signal);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Builder will run on first frame and subsequent rebuilds.
  }

  void _subscribe(dynamic signal) {
    if (!_dependencies.contains(signal)) {
      _dependencies.add(signal);
      DependencyTracker.instance.register(signal, this);
    }
  }

  void _unsubscribeAll() {
    DependencyTracker.instance.unregister(this);
    _dependencies.clear();
  }

  @override
  void markDirty() {
    if (mounted && !_isRebuilding) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _isRebuilding = true;

    // Clear old implicit dependencies before re-tracking.
    // If we have explicit signals, we keep them.
    final List<dynamic> explicitSignals = widget.signals ?? [];
    final currentDeps = Set<dynamic>.from(_dependencies);

    // We only want to remove signals that were NOT explicitly provided.
    for (final dep in currentDeps) {
      if (!explicitSignals.contains(dep)) {
        DependencyTracker.instance.unregister(this);
        _dependencies.remove(dep);
      }
    }

    late Widget result;
    DependencyTracker.instance.track(
      () {
        result = widget.builder(context);
      },
      (signal) {
        _subscribe(signal);
      },
    );

    _isRebuilding = false;
    return result;
  }

  @override
  void dispose() {
    _unsubscribeAll();
    super.dispose();
  }
}

/// A shorter alias for [SignalBuilder].
class Watch extends SignalBuilder {
  /// Creates a [Watch] widget.
  const Watch(Widget Function(BuildContext context) builder, {super.key})
    : super(builder: builder);
}
