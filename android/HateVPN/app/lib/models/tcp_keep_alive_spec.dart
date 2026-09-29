






final class TcpKeepAliveSpec {

  final bool disabled;


  final String idle;


  final String interval;

  const TcpKeepAliveSpec({
    this.disabled = false,
    this.idle = '',
    this.interval = '',
  });



  bool get isEmpty => !disabled && idle.isEmpty && interval.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TcpKeepAliveSpec &&
          other.disabled == disabled &&
          other.idle == idle &&
          other.interval == interval;

  @override
  int get hashCode => Object.hash(disabled, idle, interval);

  @override
  String toString() =>
      'TcpKeepAliveSpec(disabled: $disabled, idle: $idle, interval: $interval)';
}
