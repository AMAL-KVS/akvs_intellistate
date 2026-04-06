import 'dart:math';
import 'package:flutter/material.dart';
import 'package:akvs_intellistate/akvs_intellistate.dart';

// ─── Global Behavioral Signals ───────────────────────────────────────

final currentScreen = aiSignal(
  'home',
  name: 'currentScreen',
  behavioral: true,
  behaviorCategory: 'navigation',
);

final addToCartTaps = aiSignal(
  0,
  name: 'addToCart',
  behavioral: true,
  behaviorCategory: 'action',
);

final userSearch = aiSignal(
  '',
  name: 'userSearch',
  behavioral: true,
  behaviorCategory: 'action',
);

final filterSelection = aiSignal(
  'all',
  name: 'filter',
  behavioral: true,
  behaviorCategory: 'action',
);

// Unused behavioral signals (to demonstrate "unused" tracking)
final wishlist = aiSignal(
  <String>[],
  name: 'wishlist',
  behavioral: true,
  behaviorCategory: 'action',
);

final shareAction = aiSignal(
  0,
  name: 'share',
  behavioral: true,
  behaviorCategory: 'action',
);

final notificationPrefs = aiSignal(
  false,
  name: 'notification_prefs',
  behavioral: true,
  behaviorCategory: 'action',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  enableLearningMode(verbose: true);

  AkvsBehavior.init(
    enabled: true,
    trackScreens: true,
    trackInteractions: true,
    trackRetention: true,
    sessionGapThreshold: const Duration(minutes: 5), // short for demo
    localStoragePrefix: 'akvs_demo',
  );

  // Define a demo funnel
  AkvsFunnel.define(
    name: 'demo_checkout',
    steps: [
      FunnelStep(
        name: 'browse',
        signal: currentScreen,
        condition: (v) => v == 'product',
      ),
      FunnelStep(
        name: 'add_to_cart',
        signal: addToCartTaps,
        condition: (v) => (v as int) > 0,
      ),
      FunnelStep(
        name: 'checkout',
        signal: currentScreen,
        condition: (v) => v == 'checkout',
      ),
    ],
  );

  // Define an A/B test
  AkvsABTest.define(
    testId: 'cta_label',
    variants: {
      'control': {'label': 'Buy Now'},
      'variant_a': {'label': 'Add to Cart'},
    },
  );

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: IntelliStateDemo(),
    ),
  );
}

class IntelliStateDemo extends StatefulWidget {
  const IntelliStateDemo({super.key});

  @override
  State<IntelliStateDemo> createState() => _IntelliStateDemoState();
}

class _IntelliStateDemoState extends State<IntelliStateDemo> {
  int _currentIndex = 0;

  final screens = [
    const CounterScreen(),
    const AsyncScreen(),
    const TodoScreen(),
    const BehaviorDashboard(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.deepPurple,
        onTap: (i) {
          setState(() => _currentIndex = i);
          // Update navigation signal
          final screenNames = ['home', 'async', 'todos', 'behavior'];
          currentScreen.value = screenNames[i];
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Counter'),
          BottomNavigationBarItem(icon: Icon(Icons.cloud), label: 'Async'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Todos'),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Behavior',
          ),
        ],
      ),
    );
  }
}

// ─── SCREEN 1: COUNTER ─────────────────────────────────────────────
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  final count = aiSignal(0);
  final step = aiSignal(1);

  late final doubled = computed(() => count() * 2);
  late final label = computed(() => count() > 10 ? 'High' : 'Low');

  int rebuilds = 0;

  @override
  void initState() {
    super.initState();
    effect(() {
      debugPrint('Count changed to: ${count()}');
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    rebuilds++;
    return Scaffold(
      appBar: AppBar(title: const Text('Counter Demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Rebuilds: $rebuilds',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 20),
            Watch(
              (context) => Column(
                children: [
                  Text(
                    'Count: ${count()}',
                    style: const TextStyle(fontSize: 32),
                  ),
                  Text(
                    'Step: ${step()}',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Doubled: ${doubled()}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Chip(label: Text(label())),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => count.update((v) => v + step()),
                  child: const Text('Add Step'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => count.update((v) => v - step()),
                  child: const Text('Sub Step'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed:
                  () => batch(() {
                    count.value = 0;
                    step.value = 1;
                  }),
              child: const Text('Reset (Batched)'),
            ),
            const SizedBox(height: 20),
            const Text('Change Step:'),
            Watch(
              (context) => Slider(
                value: step().toDouble(),
                min: 1,
                max: 10,
                onChanged: (v) => step.value = v.round(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SCREEN 2: ASYNC API ───────────────────────────────────────────
class AsyncScreen extends StatefulWidget {
  const AsyncScreen({super.key});
  @override
  State<AsyncScreen> createState() => _AsyncScreenState();
}

class _AsyncScreenState extends State<AsyncScreen> {
  final userId = aiSignal(1);

  late final user = aiAsync(() async {
    final id = userId();
    await Future.delayed(const Duration(seconds: 1));
    if (Random().nextDouble() < 0.2) throw Exception('Network Failure');
    return {'id': id, 'name': 'User #$id', 'email': 'user$id@example.com'};
  }, cacheFor: const Duration(seconds: 30));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Async API Demo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('User ID: '),
                  Watch(
                    (context) => DropdownButton<int>(
                      value: userId(),
                      items:
                          [1, 2, 3, 4, 5]
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text('$id'),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => userId.value = v!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Watch(
                (context) => user().when(
                  data: (data) {
                    final map = data as Map;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(map['id'].toString()),
                        ),
                        title: Text(map['name'] as String),
                        subtitle: Text(map['email'] as String),
                      ),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error:
                      (e, s) => Column(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 48),
                          Text('Error: $e'),
                          ElevatedButton(
                            onPressed: user.refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: user.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Force Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SCREEN 3: TODO LIST ───────────────────────────────────────────
enum TodoFilter { all, active, done }

class Todo {
  final String id;
  final String text;
  final bool done;
  Todo(this.id, this.text, this.done);
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});
  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final todos = aiSignal<List<Todo>>([]);
  final filter = aiSignal(TodoFilter.all);

  late final filtered = computed(() {
    final list = todos();
    final f = filter();
    return switch (f) {
      TodoFilter.all => list,
      TodoFilter.active => list.where((t) => !t.done).toList(),
      TodoFilter.done => list.where((t) => t.done).toList(),
    };
  });

  late final allDone = computed(
    () => todos().isNotEmpty && todos().every((t) => t.done),
  );

  final controller = TextEditingController();

  void _addTodo() {
    if (controller.text.isEmpty) return;
    todos.update(
      (list) => [
        ...list,
        Todo(DateTime.now().toIso8601String(), controller.text, false),
      ],
    );
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todo List Demo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'What to do?'),
                  ),
                ),
                IconButton(onPressed: _addTodo, icon: const Icon(Icons.add)),
              ],
            ),
          ),
          Watch(
            (context) => Wrap(
              spacing: 8,
              children:
                  TodoFilter.values
                      .map(
                        (f) => ChoiceChip(
                          label: Text(f.name.toUpperCase()),
                          selected: filter() == f,
                          onSelected: (s) => filter.value = f,
                        ),
                      )
                      .toList(),
            ),
          ),
          Watch(
            (context) =>
                allDone()
                    ? Container(
                      width: double.infinity,
                      color: Colors.greenAccent,
                      padding: const EdgeInsets.all(8),
                      child: const Text(
                        '🎉 ALL DONE!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
          Expanded(
            child: Watch((context) {
              final list = filtered();
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final todo = list[i];
                  return ListTile(
                    leading: Checkbox(
                      value: todo.done,
                      onChanged: (v) {
                        todos.update(
                          (l) => [
                            for (final t in l)
                              if (t.id == todo.id)
                                Todo(t.id, t.text, v!)
                              else
                                t,
                          ],
                        );
                      },
                    ),
                    title: Text(
                      todo.text,
                      style: TextStyle(
                        decoration:
                            todo.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── SCREEN 4: BEHAVIOR DASHBOARD ──────────────────────────────────

class BehaviorDashboard extends StatelessWidget {
  const BehaviorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Behavior Intelligence'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Live Snapshot Card ──
            Watch((context) {
              final snap = BehaviorReporter.currentSnapshot;
              final dur = snap.sessionDuration;
              final durStr = '${dur.inMinutes}m ${dur.inSeconds % 60}s';
              return Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📊 Live Session',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      _metricRow('Session ID', snap.sessionId.substring(0, 12)),
                      _metricRow('Duration', durStr),
                      _metricRow(
                        'Engagement',
                        snap.engagementScore.toStringAsFixed(3),
                      ),
                      _metricRow(
                        'Frustration',
                        snap.frustrationScore.toStringAsFixed(2),
                      ),
                      _metricRow(
                        'Churn Risk',
                        snap.churnRiskScore.toStringAsFixed(2),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 12),

            // ── User Segment Chip ──
            Watch((context) {
              final seg = UserSegmentEngine.asSignal()();
              final color = switch (seg) {
                UserSegment.newUser => Colors.blue,
                UserSegment.casual => Colors.green,
                UserSegment.powerUser => Colors.deepPurple,
                UserSegment.atRisk => Colors.orange,
                UserSegment.churned => Colors.red,
              };
              return Chip(
                avatar: const Icon(Icons.person, size: 18),
                label: Text(
                  seg.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: color.withValues(alpha: 0.2),
                side: BorderSide(color: color),
              );
            }),

            const SizedBox(height: 12),

            // ── Screen Journey ──
            const Text(
              '🗺️ Screen Journey',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Watch((context) {
              final journey = ScreenTracker.sessionJourney;
              if (journey.isEmpty) {
                return const Text(
                  'No screens visited yet',
                  style: TextStyle(color: Colors.grey),
                );
              }
              return Wrap(
                spacing: 4,
                children:
                    journey.map((s) {
                      return Chip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
              );
            }),

            const SizedBox(height: 16),

            // ── Funnel Progress ──
            const Text(
              '🔊 Funnel: demo_checkout',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Watch((context) {
              // Read behavioral signals to trigger rebuilds
              currentScreen();
              addToCartTaps();
              final pct = AkvsFunnel.completionPercentage('demo_checkout');
              final status = AkvsFunnel.statusOf('demo_checkout');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.grey[200],
                    color:
                        status == FunnelStatus.completed
                            ? Colors.green
                            : Colors.deepPurple,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(pct * 100).round()}% complete · ${status.name}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _funnelBtn('Browse (product)', () {
                        currentScreen.value = 'product';
                      }),
                      _funnelBtn('Add to Cart', () {
                        addToCartTaps.update((v) => v + 1);
                      }),
                      _funnelBtn('Checkout', () {
                        currentScreen.value = 'checkout';
                      }),
                    ],
                  ),
                ],
              );
            }),

            const SizedBox(height: 16),

            // ── Simulate Rage Tap ──
            const Text(
              '😡 Rage Tap Simulation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[50],
                foregroundColor: Colors.red,
              ),
              onPressed: () {
                // Rapid writes to trigger rage tap detection
                for (int i = 0; i < 4; i++) {
                  addToCartTaps.value = addToCartTaps.value + 1;
                }
              },
              icon: const Icon(Icons.touch_app),
              label: const Text('Simulate 4 rapid taps'),
            ),
            const SizedBox(height: 4),
            Watch((context) {
              addToCartTaps(); // subscribe for updates
              final taps = InteractionTracker.rageTapsThisSession;
              if (taps.isEmpty) {
                return const Text(
                  'No rage taps detected',
                  style: TextStyle(color: Colors.grey),
                );
              }
              return Column(
                children:
                    taps
                        .map(
                          (r) => Text(
                            '⚠ ${r.signalName}: ${r.tapCount}x in ${r.within.inMilliseconds}ms',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        )
                        .toList(),
              );
            }),

            const SizedBox(height: 16),

            // ── A/B Test Card ──
            const Text(
              '🧪 A/B Test: cta_label',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Watch((context) {
              final variant = AkvsABTest.asSignal('cta_label')();
              final label =
                  AkvsABTest.variantValue('cta_label', 'label') ?? 'unknown';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Variant: $variant',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text('CTA Label: "$label"'),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed:
                            () => AkvsABTest.recordConversion('cta_label'),
                        child: const Text('Record Conversion'),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // ── Feature Usage ──
            const Text(
              '📈 Feature Usage (this session)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Watch((context) {
              // Subscribe to some signals to trigger rebuilds
              addToCartTaps();
              final usage = FeatureTracker.featureUsageThisSession;
              if (usage.isEmpty) {
                return const Text(
                  'No features used yet',
                  style: TextStyle(color: Colors.grey),
                );
              }
              final sorted =
                  usage.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
              return Column(
                children:
                    sorted.take(5).map((e) {
                      final maxVal = sorted.first.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                e.key,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: maxVal > 0 ? e.value / maxVal : 0,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              );
            }),

            const SizedBox(height: 8),
            Watch((context) {
              addToCartTaps(); // trigger rebuild
              final unused = FeatureTracker.unusedSignalsThisSession;
              if (unused.isEmpty) return const SizedBox.shrink();
              return Text(
                'Unused: ${unused.join(', ')}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              );
            }),

            const SizedBox(height: 16),

            // ── Retention Grid ──
            const Text(
              '📅 Last 7 Days Activity',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Watch((context) {
              final activity = RetentionTracker.last7DaysActivity;
              final labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final active = i < activity.length && activity[i];
                  return Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: active ? Colors.green : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child:
                            active
                                ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                                : null,
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i], style: const TextStyle(fontSize: 10)),
                    ],
                  );
                }),
              );
            }),

            const SizedBox(height: 8),
            Watch((context) {
              return Text(
                'DAU streak: ${RetentionTracker.dauStreak} · '
                'WAU: ${RetentionTracker.wauCount} · '
                'MAU: ${RetentionTracker.mauCount}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              );
            }),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _funnelBtn(String label, VoidCallback onTap) => ElevatedButton(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );
}
