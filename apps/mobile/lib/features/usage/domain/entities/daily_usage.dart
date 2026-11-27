import 'package:meta/meta.dart';

int _int(Object? value) => value is num ? value.toInt() : 0;

@immutable
class UsageBalance {
  const UsageBalance({
    required this.limit,
    required this.used,
    required this.reserved,
    required this.available,
  });

  factory UsageBalance.fromJson(Map<String, Object?> json) => UsageBalance(
    limit: _int(json['limit']),
    used: _int(json['used']),
    reserved: _int(json['reserved']),
    available: _int(json['available']),
  );

  final int limit;
  final int used;
  final int reserved;
  final int available;

  bool get isExhausted => available <= 0;

  UsageBalance spend() => UsageBalance(
    limit: limit,
    used: used + 1,
    reserved: reserved,
    available: available > 0 ? available - 1 : 0,
  );

  @override
  bool operator ==(Object other) =>
      other is UsageBalance &&
      other.limit == limit &&
      other.used == used &&
      other.reserved == reserved &&
      other.available == available;

  @override
  int get hashCode => Object.hash(limit, used, reserved, available);
}

@immutable
class DailyUsage {
  const DailyUsage({
    required this.bucket,
    required this.resetsAt,
    required this.pro,
    required this.profileComplete,
    required this.likes,
    required this.searches,
  });

  factory DailyUsage.fromJson(Map<String, Object?> json) => DailyUsage(
    bucket: json['bucket'] as String? ?? '',
    resetsAt: DateTime.parse(json['resets_at']! as String),
    pro: json['pro'] as bool? ?? false,
    profileComplete: json['profile_complete'] as bool? ?? false,
    likes: UsageBalance.fromJson((json['likes'] as Map).cast()),
    searches: UsageBalance.fromJson((json['searches'] as Map).cast()),
  );

  final String bucket;

  /// Next WIB midnight, sent in UTC. Format it in the device zone; never
  /// compute the reset locally.
  final DateTime resetsAt;
  final bool pro;
  final bool profileComplete;
  final UsageBalance likes;
  final UsageBalance searches;

  DailyUsage copyWith({UsageBalance? likes, UsageBalance? searches}) =>
      DailyUsage(
        bucket: bucket,
        resetsAt: resetsAt,
        pro: pro,
        profileComplete: profileComplete,
        likes: likes ?? this.likes,
        searches: searches ?? this.searches,
      );

  @override
  bool operator ==(Object other) =>
      other is DailyUsage &&
      other.bucket == bucket &&
      other.resetsAt == resetsAt &&
      other.pro == pro &&
      other.profileComplete == profileComplete &&
      other.likes == likes &&
      other.searches == searches;

  @override
  int get hashCode =>
      Object.hash(bucket, resetsAt, pro, profileComplete, likes, searches);
}
