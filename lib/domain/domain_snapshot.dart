/// An immutable snapshot representing the state of a [DomainStore] at a point in time.
///
/// Snapshots are useful for implementing undo/redo, time-travel debugging,
/// or saving state offline without worrying about mutable references.
class DomainSnapshot<T> {
  /// The timestamp when this snapshot was created.
  final DateTime timestamp;

  /// The strongly-typed immutable data payload of the snapshot.
  final T data;

  DomainSnapshot(this.data, {DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// Creates a snapshot with an explicit timestamp. Useful for hydration.
  const DomainSnapshot.withTime(this.data, this.timestamp);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DomainSnapshot<T> &&
        other.timestamp == timestamp &&
        other.data == data;
  }

  @override
  int get hashCode => timestamp.hashCode ^ data.hashCode;

  @override
  String toString() => 'DomainSnapshot(time: $timestamp, data: $data)';
}
