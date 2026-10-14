enum StorageLevel { normal, warning, critical, full }

class StorageBudget {
  const StorageBudget(this.used, this.limit);
  final BigInt used, limit;
  static StorageBudget? read(dynamic used, dynamic limit) {
    final u = BigInt.tryParse('$used');
    final l = BigInt.tryParse('$limit');
    if (u == null || l == null || u.isNegative || l <= BigInt.zero) return null;
    return StorageBudget(u, l);
  }

  StorageLevel get level {
    if (used >= limit) return StorageLevel.full;
    if (used * BigInt.from(100) >= limit * BigInt.from(95)) {
      return StorageLevel.critical;
    }
    if (used * BigInt.from(100) >= limit * BigInt.from(80)) {
      return StorageLevel.warning;
    }
    return StorageLevel.normal;
  }

  double get fraction => (used.toDouble() / limit.toDouble()).clamp(0, 1);
  String get percent =>
      (used.toDouble() / limit.toDouble() * 100).toStringAsFixed(1);
}
