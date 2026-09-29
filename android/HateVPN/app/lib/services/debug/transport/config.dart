

class DebugServerConfig {
  const DebugServerConfig({
    required this.port,
    required this.token,
    this.requestTimeout = const Duration(seconds: 30),
    this.maxBodyBytes = 1024 * 1024,
    this.unauthenticatedPaths = const {'/ping', '/help'},
  });


  final int port;


  final String token;


  final Duration requestTimeout;





  final int maxBodyBytes;



  final Set<String> unauthenticatedPaths;
}
