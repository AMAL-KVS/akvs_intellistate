## 1.0.0

### 🚀 Initial Release

#### Core Reactive Engine
- **Signal\<T\>** — Reactive state atoms with auto-dependency tracking
- **Computed\<T\>** — Lazy derived values with intelligent caching
- **Effect** — Auto-tracked side effects with cleanup lifecycle
- **AsyncSignal\<T\>** — Reactive async computations with loading/data/error states
- **UpdateScheduler** — Priority-based batch scheduler (Computed first, Effects second)
- **DependencyTracker** — Zone-based dependency graph with zero leaks
- **MemoryManager** — Auto-dispose GC for unused signals

#### Flutter Integration
- **Watch** / **SignalBuilder** — Reactive widgets that auto-rebuild on signal changes
- **WatchExtension** — `context.watch(signal)` for StatelessWidget support
- **batch()** — Coalesce multiple writes into a single rebuild

#### Behavior Intelligence
- **SessionTracker** — Session lifecycle, duration, signal write count, engagement score
- **ScreenTracker** — Auto screen journey tracking via navigation-tagged signals
- **InteractionTracker** — Rage tap detection (≥3 writes in 1s), frustration scoring
- **FunnelTracker** — Declarative multi-step funnel definitions with step/complete/abandon events
- **FeatureTracker** — Signal usage heatmap, most/least used, unused feature detection
- **UserSegmentEngine** — 5 user cohorts: newUser, casual, powerUser, atRisk, churned
- **RetentionTracker** — DAU streak, WAU/MAU, churn risk scoring with reactive signals
- **AkvsABTest** — Deterministic A/B variant assignment, conversion tracking, reactive signals
- **BehaviorReporter** — Unified snapshot, GA4 event mapping, SharedPreferences persistence
- **10 sealed event types** — SessionStart/End, ScreenView/Leave, UserAction, RageTap, FunnelStep/Complete/Abandon, RetentionSnapshot

#### DevTools
- **Learning Mode** — Real-time 30-second performance summaries with behavior intelligence report

#### Privacy & GDPR
- Zero PII — no signal values stored, only names and type names
- `BehaviorReporter.clearAll()` — complete data erasure for GDPR compliance
- All SharedPreferences writes are async fire-and-forget

#### Hard Guarantees
- ✅ Zero manual tracking calls required
- ✅ Zero overhead when behavior module is not initialized
- ✅ Zero breaking changes — all new parameters are optional
- ✅ Private `_BehaviorBus` — no public API pollution
- ✅ All persistence is async, never blocks UI thread
