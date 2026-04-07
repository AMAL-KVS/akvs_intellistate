import 'package:flutter/material.dart';
import '../core/memory_manager.dart';
import 'learning_mode.dart';

/// A draggable debug overlay showing real-time signal metrics.
///
/// Automatically disabled in release mode.
/// Usage: Wrap your root widget (or MaterialApp builder):
/// ```dart
///   runApp(
///     AkvsInspectorOverlay(
///       child: MyApp(),
///     ),
///   );
/// ```
class AkvsInspectorOverlay extends StatefulWidget {
  final Widget child;

  const AkvsInspectorOverlay({super.key, required this.child});

  @override
  State<AkvsInspectorOverlay> createState() => _AkvsInspectorOverlayState();
}

class _AkvsInspectorOverlayState extends State<AkvsInspectorOverlay> {
  bool _expanded = false;
  Offset _position = const Offset(20, kToolbarHeight + 50);

  @override
  Widget build(BuildContext context) {
    // Only render the wrapper in release mode to ensure zero overhead.
    if (const bool.fromEnvironment('dart.vm.product')) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
              });
            },
            child: Material(
              color: Colors.transparent,
              elevation: _expanded ? 8 : 4,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _expanded ? 320 : 60,
                height: _expanded ? 400 : 60,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: _expanded ? _buildExpanded() : _buildCollapsed(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsed() {
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: Icon(Icons.bug_report, color: Colors.blueAccent.shade100),
      ),
    );
  }

  Widget _buildExpanded() {
    final stats = MemoryManager.instance.stats;
    final int signalCount = stats['signal_count'] ?? 0;
    final int activeListeners = stats['active_listener_count'] ?? 0;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'IntelliState Inspector',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                onPressed: () => setState(() => _expanded = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // Live stats ticker
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatBadge('Signals', signalCount.toString(), Colors.blue),
              _StatBadge('Listeners', activeListeners.toString(), Colors.green),
            ],
          ),
        ),

        // Signal List
        Expanded(
          child: ListView.builder(
            itemCount: 0, // In a real implementation we would track active signals
            itemBuilder: (context, index) {
              return const SizedBox(); // Stub for search/filter signal list
            },
          ),
        ),

        // Footer Actions
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white24)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    MemoryManager.instance.disposeAll();
                  },
                  child: const Text('Force GC'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple.shade800,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    // Turn on learning mode instantly
                    enableLearningMode(verbose: true);
                  },
                  child: const Text('Learn Mode'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
