import '../services/format_utils.dart';





class TrafficSnapshot {
  const TrafficSnapshot({
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.activeConnections = 0,
    this.connectionsIn = 0,
    this.connectionsOut = 0,
    this.memory = 0,
    this.byRule = const {},
    this.byApp = const {},
  });

  final int uploadTotal;
  final int downloadTotal;


  final int activeConnections;





  final int connectionsIn;
  final int connectionsOut;


  final int memory;



  final Map<String, int> byRule;


  final Map<String, AppStat> byApp;

  static const zero = TrafficSnapshot();

  String get uploadFormatted => formatBytes(uploadTotal);
  String get downloadFormatted => formatBytes(downloadTotal);
  String get memoryFormatted => formatBytes(memory);
}

class AppStat {
  const AppStat({this.count = 0, this.upload = 0, this.download = 0});
  final int count;
  final int upload;
  final int download;

  static const zero = AppStat();

  int get totalBytes => upload + download;
}
