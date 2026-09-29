import 'node_warning.dart';
import 'template_vars.dart';




sealed class TransportSpec {
  const TransportSpec();

  (Map<String, dynamic> map, List<NodeWarning> warnings) toSingbox(
      TemplateVars vars);
}

final class WsTransport extends TransportSpec {
  final String path;
  final String host;
  final Map<String, String> headers;





  final int? maxEarlyData;
  final String? earlyDataHeaderName;







  final bool earlyDataHeaderImplicit;

  const WsTransport({
    this.path = '',
    this.host = '',
    this.headers = const {},
    this.maxEarlyData,
    this.earlyDataHeaderName,
    this.earlyDataHeaderImplicit = false,
  });

  @override
  (Map<String, dynamic>, List<NodeWarning>) toSingbox(TemplateVars vars) {






    final m = <String, dynamic>{
      'type': 'ws',
      if (path.isNotEmpty) 'path': path,
    };
    if (host.isNotEmpty) {
      m['headers'] = {'Host': host, ...headers};
    } else if (headers.isNotEmpty) {
      m['headers'] = Map<String, String>.from(headers);
    }
    if (maxEarlyData != null) {
      m['max_early_data'] = maxEarlyData;
    }
    if (earlyDataHeaderName != null) {
      m['early_data_header_name'] = earlyDataHeaderName;
    }
    return (m, const []);
  }
}

final class GrpcTransport extends TransportSpec {
  final String serviceName;
  const GrpcTransport({required this.serviceName});

  @override
  (Map<String, dynamic>, List<NodeWarning>) toSingbox(TemplateVars vars) => (
        {'type': 'grpc', 'service_name': serviceName},
        const [],
      );
}

final class HttpTransport extends TransportSpec {
  final String path;
  final List<String> hosts;
  final Map<String, String> headers;

  const HttpTransport({
    this.path = '/',
    this.hosts = const [],
    this.headers = const {},
  });

  @override
  (Map<String, dynamic>, List<NodeWarning>) toSingbox(TemplateVars vars) {
    final m = <String, dynamic>{'type': 'http', 'path': path};
    if (hosts.isNotEmpty) m['host'] = List<String>.from(hosts);
    if (headers.isNotEmpty) m['headers'] = Map<String, String>.from(headers);
    return (m, const []);
  }
}

final class HttpUpgradeTransport extends TransportSpec {
  final String path;
  final String host;





  final Map<String, String> headers;

  const HttpUpgradeTransport({
    this.path = '',
    this.host = '',
    this.headers = const {},
  });

  @override
  (Map<String, dynamic>, List<NodeWarning>) toSingbox(TemplateVars vars) {


    final m = <String, dynamic>{
      'type': 'httpupgrade',
      if (path.isNotEmpty) 'path': path,
    };
    if (host.isNotEmpty) m['host'] = host;
    if (headers.isNotEmpty) m['headers'] = Map<String, String>.from(headers);
    return (m, const []);
  }
}




















final class XhttpTransport extends TransportSpec {

  final String path;
  final String host;
  final String mode;
  final String xPaddingBytes;
  final bool noGrpcHeader;
  final Map<String, String> headers;


  final String sessionPlacement;
  final String sessionKey;
  final String seqPlacement;
  final String seqKey;


  final String uplinkDataPlacement;
  final String uplinkDataKey;
  final String uplinkChunkSize;
  final String uplinkHttpMethod;


  final bool xPaddingObfsMode;
  final String xPaddingKey;
  final String xPaddingHeader;
  final String xPaddingPlacement;
  final String xPaddingMethod;


  final String scMaxEachPostBytes;
  final String scMinPostsIntervalMs;
  final String scStreamUpServerSecs;



  final int scMaxBufferedPosts;


  final bool noSseHeader;



  final String maxConnections;
  final String maxConcurrency;
  final String cMaxReuseTimes;
  final String hMaxRequestTimes;
  final String hMaxReusableSecs;
  final int hKeepAlivePeriod;

  const XhttpTransport({
    this.path = '/',
    this.host = '',
    this.mode = '',
    this.xPaddingBytes = '',
    this.noGrpcHeader = false,
    this.headers = const {},
    this.sessionPlacement = '',
    this.sessionKey = '',
    this.seqPlacement = '',
    this.seqKey = '',
    this.uplinkDataPlacement = '',
    this.uplinkDataKey = '',
    this.uplinkChunkSize = '',
    this.uplinkHttpMethod = '',
    this.xPaddingObfsMode = false,
    this.xPaddingKey = '',
    this.xPaddingHeader = '',
    this.xPaddingPlacement = '',
    this.xPaddingMethod = '',
    this.scMaxEachPostBytes = '',
    this.scMinPostsIntervalMs = '',
    this.scStreamUpServerSecs = '',
    this.scMaxBufferedPosts = -1,
    this.noSseHeader = false,
    this.maxConnections = '',
    this.maxConcurrency = '',
    this.cMaxReuseTimes = '',
    this.hMaxRequestTimes = '',
    this.hMaxReusableSecs = '',
    this.hKeepAlivePeriod = -1,
  });

  @override
  (Map<String, dynamic>, List<NodeWarning>) toSingbox(TemplateVars vars) {




    final m = <String, dynamic>{'type': 'xhttp'};
    if (path.isNotEmpty) m['path'] = path;
    final warnings = <NodeWarning>[];







    if (host.isNotEmpty) m['host'] = host;
    if (mode.isNotEmpty) m['mode'] = mode;
    if (xPaddingBytes.isNotEmpty) m['x_padding_bytes'] = xPaddingBytes;
    if (noGrpcHeader) m['no_grpc_header'] = true;
    if (noSseHeader) m['no_sse_header'] = true;
    if (headers.isNotEmpty) m['headers'] = Map<String, String>.from(headers);

    if (sessionPlacement.isNotEmpty) {
      m['session_placement'] = sessionPlacement;
    }
    if (sessionKey.isNotEmpty) m['session_key'] = sessionKey;
    if (seqPlacement.isNotEmpty) m['seq_placement'] = seqPlacement;
    if (seqKey.isNotEmpty) m['seq_key'] = seqKey;










    if (uplinkDataPlacement.isNotEmpty) {
      m['uplink_data_placement'] = uplinkDataPlacement;
    }
    if (uplinkDataKey.isNotEmpty) m['uplink_data_key'] = uplinkDataKey;
    if (uplinkChunkSize.isNotEmpty) m['uplink_chunk_size'] = uplinkChunkSize;





    if (uplinkHttpMethod.isNotEmpty) {
      m['uplink_http_method'] = uplinkHttpMethod;
    }

    if (xPaddingObfsMode) m['x_padding_obfs_mode'] = true;
    if (xPaddingKey.isNotEmpty) m['x_padding_key'] = xPaddingKey;
    if (xPaddingHeader.isNotEmpty) m['x_padding_header'] = xPaddingHeader;
    if (xPaddingPlacement.isNotEmpty) {
      m['x_padding_placement'] = xPaddingPlacement;
    }
    if (xPaddingMethod.isNotEmpty) m['x_padding_method'] = xPaddingMethod;
    if (scMaxEachPostBytes.isNotEmpty) {
      m['sc_max_each_post_bytes'] = scMaxEachPostBytes;
    }
    if (scMinPostsIntervalMs.isNotEmpty) {
      m['sc_min_posts_interval_ms'] = scMinPostsIntervalMs;
    }
    if (scStreamUpServerSecs.isNotEmpty) {
      m['sc_stream_up_server_secs'] = scStreamUpServerSecs;
    }

    if (scMaxBufferedPosts >= 0) m['sc_max_buffered_posts'] = scMaxBufferedPosts;



    final xmux = <String, dynamic>{};
    if (maxConcurrency.isNotEmpty) xmux['max_concurrency'] = maxConcurrency;
    if (maxConnections.isNotEmpty) xmux['max_connections'] = maxConnections;
    if (cMaxReuseTimes.isNotEmpty) xmux['c_max_reuse_times'] = cMaxReuseTimes;
    if (hMaxRequestTimes.isNotEmpty) {
      xmux['h_max_request_times'] = hMaxRequestTimes;
    }
    if (hMaxReusableSecs.isNotEmpty) {
      xmux['h_max_reusable_secs'] = hMaxReusableSecs;
    }
    if (hKeepAlivePeriod >= 0) xmux['h_keep_alive_period'] = hKeepAlivePeriod;
    if (xmux.isNotEmpty) m['xmux'] = xmux;

    return (m, warnings);
  }
}
