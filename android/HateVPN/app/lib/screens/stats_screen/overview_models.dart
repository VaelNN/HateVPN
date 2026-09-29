


class OutboundGroup {
  OutboundGroup({required this.name, this.upload = 0, this.download = 0, required this.connections});
  final String name;
  int upload;
  int download;
  final List<Connection> connections;
}

class Connection {
  Connection({
    required this.host,
    this.destPort = '',
    this.network = '',
    this.rule = '',
    this.upload = 0,
    this.download = 0,
    this.start = 0,
  });


  final String host;


  final String destPort;
  final String network;
  final String rule;
  final int upload;
  final int download;


  final int start;
}
