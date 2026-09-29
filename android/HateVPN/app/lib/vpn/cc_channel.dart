import 'dart:async';

import 'package:flutter/services.dart';

import '../services/platform_channels.dart';
import '../services/selector_info.dart';













class CcChannel {
  CcChannel._();

  static final CcChannel instance = CcChannel._();

  static const MethodChannel _methods = MethodChannel(PlatformChannels.methods);

  static const EventChannel _statusChannel = EventChannel(
    PlatformChannels.ccStatus,
  );
  static const EventChannel _outboundsChannel = EventChannel(
    PlatformChannels.ccOutbounds,
  );
  static const EventChannel _groupsChannel = EventChannel(
    PlatformChannels.ccGroups,
  );
  static const EventChannel _connectionsChannel = EventChannel(
    PlatformChannels.ccConnections,
  );
  static const EventChannel _dnsChannel = EventChannel(
    PlatformChannels.ccDns,
  );
  static const EventChannel _tailscaleChannel = EventChannel(
    PlatformChannels.ccTailscale,
  );
  static const EventChannel _tailscalePingChannel = EventChannel(
    PlatformChannels.ccTailscalePing,
  );
















  late final Stream<CcStatus> _statusStream = _sharedStream<CcStatus>(
    _statusChannel,
    (e) => CcStatus.fromMap(_asMap(e)),
  );
  late final Stream<List<CcOutbound>> _outboundsStream =
      _sharedStream<List<CcOutbound>>(
        _outboundsChannel,
        (e) => _asList(e).map((m) => CcOutbound.fromMap(_asMap(m))).toList(),
      );
  late final Stream<List<CcGroup>> _groupsStream = _sharedStream<List<CcGroup>>(
    _groupsChannel,
    (e) => _asList(e).map((m) => CcGroup.fromMap(_asMap(m))).toList(),
  );
  late final Stream<List<CcConnection>> _connectionsStream =
      _sharedStream<List<CcConnection>>(
        _connectionsChannel,
        (e) => _asList(e).map((m) => CcConnection.fromMap(_asMap(m))).toList(),
      );

  late final Stream<List<CcDnsQuery>> _dnsQueriesStream =
      _sharedStream<List<CcDnsQuery>>(
        _dnsChannel,
        (e) => _asList(e).map((m) => CcDnsQuery.fromMap(_asMap(m))).toList(),
      );



  Stream<CcStatus> get status => _statusStream;


  Stream<List<CcOutbound>> get outbounds => _outboundsStream;


  Stream<List<CcGroup>> get groups => _groupsStream;



  Stream<List<CcConnection>> get connections => _connectionsStream;



  Stream<List<CcDnsQuery>> get dnsQueries => _dnsQueriesStream;


  late final Stream<List<CcTailscaleStatus>> _tailscaleStream =
      _sharedStream<List<CcTailscaleStatus>>(
        _tailscaleChannel,
        CcTailscaleStatus.listFrom,
      );




  Stream<List<CcTailscaleStatus>> get tailscaleStatus => _tailscaleStream;




  late final Stream<CcTailscalePingResult> _tailscalePingStream =
      _tailscalePingChannel.receiveBroadcastStream().map(
            (e) => CcTailscalePingResult.fromMap(_asMap(e)),
          );


  Stream<CcTailscalePingResult> get tailscalePing => _tailscalePingStream;




















  final List<void Function()> _cacheResetters = [];




  void resetCaches() {
    for (final reset in _cacheResetters) {
      reset();
    }
  }

  Stream<T> _sharedStream<T>(EventChannel channel, T Function(Object?) decode) {
    T? last;
    var hasLast = false;
    final controller = StreamController<T>.broadcast(
      onListen: () {},
    );
    _cacheResetters.add(() {
      last = null;
      hasLast = false;
    });

    channel.receiveBroadcastStream().listen(
      (e) {
        last = decode(e);
        hasLast = true;
        if (!controller.isClosed) controller.add(last as T);
      },
      onError: (Object err, StackTrace st) {
        if (!controller.isClosed) controller.addError(err, st);
      },
    );


    return Stream<T>.multi((sub) {
      if (hasLast) sub.add(last as T);
      final inner = controller.stream.listen(
        sub.add,
        onError: sub.addError,
        onDone: sub.close,
      );
      sub.onCancel = inner.cancel;
    });
  }









  Future<void> resyncForReopen() => _invoke('ccResyncForReopen');

  Future<void> connectScreen() => _invoke('ccConnectScreen');
  Future<void> disconnectScreen() => _invoke('ccDisconnectScreen');
  Future<void> connectProfiler() => _invoke('ccConnectProfiler');
  Future<void> disconnectProfiler() => _invoke('ccDisconnectProfiler');








  int _profilerRefs = 0;
  Future<void> acquireProfiler() async {
    _profilerRefs++;
    if (_profilerRefs == 1) await connectProfiler();
  }

  Future<void> releaseProfiler() async {
    if (_profilerRefs == 0) return;
    _profilerRefs--;
    if (_profilerRefs == 0) await disconnectProfiler();
  }




  Future<void> cancelPing() => _invoke('ccCancelPing');


  Future<void> startTailscaleStatus() => _invoke('ccStartTailscaleStatus');
  Future<void> stopTailscaleStatus() => _invoke('ccStopTailscaleStatus');



  int _tailscaleRefs = 0;
  Future<void> acquireTailscaleStatus() async {
    _tailscaleRefs++;
    if (_tailscaleRefs == 1) await startTailscaleStatus();
  }

  Future<void> releaseTailscaleStatus() async {
    if (_tailscaleRefs == 0) return;
    _tailscaleRefs--;
    if (_tailscaleRefs == 0) await stopTailscaleStatus();
  }


  Future<void> restartTailscaleStatus() async {
    if (_tailscaleRefs > 0) await startTailscaleStatus();
  }



  Future<String?> setTailscaleExitNode(String tag, String stableId) =>
      _invokeError('ccSetTailscaleExitNode', {
        'tag': tag,
        'stable_id': stableId,
      });


  Future<String?> tailscaleLogout(String tag) =>
      _invokeError('ccTailscaleLogout', {'tag': tag});


  Future<void> startTailscalePing(String tag, String peerIp) async {
    try {
      await _methods.invokeMethod<void>('ccStartTailscalePing', {
        'tag': tag,
        'peer_ip': peerIp,
      });
    } on PlatformException {

    } on MissingPluginException {

    }
  }

  Future<void> stopTailscalePing() => _invoke('ccStopTailscalePing');

  Future<String?> _invokeError(String method, Map<String, Object> args) async {
    try {
      return await _methods.invokeMethod<String>(method, args);
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } on MissingPluginException {
      return 'not available';
    }
  }




  Future<void> setStatusFast(bool fast) async {
    try {
      await _methods.invokeMethod<void>('ccSetStatusFast', {'fast': fast});
    } catch (_) {

    }
  }




  Future<void> pauseClients() => _invoke('ccPauseClients');


  Future<void> resumeClients() => _invoke('ccResumeClients');






  Future<CcDelayResult> urlTestOutbound(
    String tag, {
    String link = '',
    int timeoutMs = 0,
  }) async {
    final r = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'ccUrlTestOutbound',
      {'tag': tag, 'link': link, 'timeoutMs': timeoutMs},
    );
    return CcDelayResult.fromMap(_asMap(r ?? const {}));
  }





  Future<bool> urlTestGroup(String tag) async =>
      await _methods.invokeMethod<bool>('ccUrlTestGroup', {'tag': tag}) ??
      false;






  Future<String> probeStart(String config) async {
    final r = await _methods.invokeMethod<String>('probeStart', {
      'config': config,
    });
    return r ?? '';
  }



  Future<CcDelayResult> probeUrlTest(
    String tag, {
    String link = '',
    int timeoutMs = 0,
  }) async {
    final r = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'probeUrlTest',
      {'tag': tag, 'link': link, 'timeoutMs': timeoutMs},
    );
    return CcDelayResult.fromMap(_asMap(r ?? const {}));
  }



  Future<CcGetUrlResult> probeGetUrl(
    String tag, {
    required String link,
    int timeoutMs = 0,
    int maxBytes = 0,
  }) async {
    final r = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'probeGetUrl',
      {'tag': tag, 'link': link, 'timeoutMs': timeoutMs, 'maxBytes': maxBytes},
    );
    return CcGetUrlResult.fromMap(_asMap(r ?? const {}));
  }


  Future<void> probeStop() => _methods.invokeMethod<void>('probeStop');









  Future<CcGetUrlResult> getUrlViaOutbound(
    String tag, {
    required String link,
    int timeoutMs = 0,
    int maxBytes = 0,
  }) async {
    final r = await _methods.invokeMethod<Map<dynamic, dynamic>>(
      'ccGetUrlViaOutbound',
      {'tag': tag, 'link': link, 'timeoutMs': timeoutMs, 'maxBytes': maxBytes},
    );
    return CcGetUrlResult.fromMap(_asMap(r ?? const {}));
  }


  Future<List<CcRule>> getRules() async {
    final r = await _methods.invokeMethod<List<dynamic>>('ccGetRules');
    return (r ?? const []).map((m) => CcRule.fromMap(_asMap(m))).toList();
  }







  Future<List<CcGroup>?> getGroups() async {
    final r = await _methods.invokeMethod<List<dynamic>>('ccGetGroups');
    if (r == null) return null;
    return r.map((m) => CcGroup.fromMap(_asMap(m))).toList();
  }






  Future<List<CcOutbound>?> getOutbounds() async {
    final r = await _methods.invokeMethod<List<dynamic>>('ccGetOutbounds');
    if (r == null) return null;
    return r.map((m) => CcOutbound.fromMap(_asMap(m))).toList();
  }










  Future<String?> getRunningConfig() async {
    try {
      final r = await _methods.invokeMethod<String>('ccGetRunningConfig');
      return (r == null || r.isEmpty) ? null : r;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }









  Future<List<CcPoolSlot>?> getPool(String tag) async {
    final r = await _methods.invokeMethod<List<dynamic>>('ccGetPool', {
      'tag': tag,
    });
    if (r == null) return null;
    return r.map((m) => CcPoolSlot.fromMap(_asMap(m))).toList();
  }







  Future<List<CcDnsGroup>?> getDnsGroups() async {
    try {
      final r = await _methods.invokeMethod<List<dynamic>>('ccGetDnsGroups');
      if (r == null) return null;
      return [
        for (final e in r)
          if (e is Map) CcDnsGroup.fromMap(_asMap(e)),
      ];
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> selectOutbound(String group, String tag) async =>
      await _methods.invokeMethod<bool>('ccSelectOutbound', {
        'group': group,
        'tag': tag,
      }) ??
      false;






  Future<String> setEndpointEnabled(String tag, bool enabled) async =>
      await _methods.invokeMethod<String>('ccSetEndpointEnabled', {
        'tag': tag,
        'enabled': enabled,
      }) ??
      '';

  Future<bool> closeConnection(String id) async =>
      await _methods.invokeMethod<bool>('ccCloseConnection', {'id': id}) ??
      false;

  Future<bool> closeConnections() async =>
      await _methods.invokeMethod<bool>('ccCloseConnections') ?? false;

  Future<void> _invoke(String method) async {
    try {
      await _methods.invokeMethod<void>(method);
    } on PlatformException {

    } on MissingPluginException {

    }
  }

  static Map<String, dynamic> _asMap(Object? e) {
    if (e is Map) {
      return e.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  static List<dynamic> _asList(Object? e) => e is List ? e : const [];
}









class CcTailscaleStatus {
  const CcTailscaleStatus({
    required this.tag,
    required this.backendState,
    required this.stateText,
    this.authUrl = '',
    this.networkName = '',
    this.magicDnsSuffix = '',
    this.keyAuth = false,
    this.self,
    this.exitNode,
    this.userGroups = const [],
  });

  final String tag;
  final String backendState;
  final String stateText;
  final String authUrl;
  final String networkName;
  final String magicDnsSuffix;
  final bool keyAuth;


  final CcTailscalePeer? self;


  final CcTailscalePeer? exitNode;


  final List<CcTailscaleUserGroup> userGroups;


  List<CcTailscalePeer> get peers => [
        for (final g in userGroups) ...g.peers,
      ];

  factory CcTailscaleStatus.fromMap(Map<String, dynamic> m) {
    final self = m['self'];
    final exit = m['exit_node'];
    return CcTailscaleStatus(
      tag: '${m['tag'] ?? ''}',
      backendState: '${m['backend_state'] ?? ''}',
      stateText: '${m['state_text'] ?? ''}',
      authUrl: '${m['auth_url'] ?? ''}',
      networkName: '${m['network_name'] ?? ''}',
      magicDnsSuffix: '${m['magic_dns_suffix'] ?? ''}',
      keyAuth: m['key_auth'] == true,
      self: self is Map ? CcTailscalePeer.fromMap(CcChannel._asMap(self)) : null,
      exitNode:
          exit is Map ? CcTailscalePeer.fromMap(CcChannel._asMap(exit)) : null,
      userGroups: [
        for (final g in CcChannel._asList(m['user_groups']))
          if (g is Map) CcTailscaleUserGroup.fromMap(CcChannel._asMap(g)),
      ],
    );
  }



  static List<CcTailscaleStatus> listFrom(Object? e) => [
        for (final m in CcChannel._asList(e))
          if (m is Map)
            CcTailscaleStatus.fromMap(CcChannel._asMap(m)),
      ].where((s) => s.tag.isNotEmpty).toList();
}



class CcTailscalePeer {
  const CcTailscalePeer({
    this.stableId = '',
    this.hostName = '',
    this.dnsName = '',
    this.os = '',
    this.online = false,
    this.exitNode = false,
    this.exitNodeOption = false,
    this.shareeNode = false,
    this.expired = false,
    this.keyExpiry = 0,
    this.lastSeen = 0,
    this.ips = const [],
  });

  final String stableId;
  final String hostName;
  final String dnsName;
  final String os;
  final bool online;


  final bool exitNode;


  final bool exitNodeOption;
  final bool shareeNode;
  final bool expired;
  final int keyExpiry;
  final int lastSeen;
  final List<String> ips;


  String get dnsNameClean =>
      dnsName.endsWith('.') ? dnsName.substring(0, dnsName.length - 1) : dnsName;


  String get firstIp => ips.isEmpty ? '' : ips.first;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  factory CcTailscalePeer.fromMap(Map<String, dynamic> m) => CcTailscalePeer(
        stableId: '${m['stable_id'] ?? ''}',
        hostName: '${m['host_name'] ?? ''}',
        dnsName: '${m['dns_name'] ?? ''}',
        os: '${m['os'] ?? ''}',
        online: m['online'] == true,
        exitNode: m['exit_node'] == true,
        exitNodeOption: m['exit_node_option'] == true,
        shareeNode: m['sharee_node'] == true,
        expired: m['expired'] == true,
        keyExpiry: _int(m['key_expiry']),
        lastSeen: _int(m['last_seen']),
        ips: [
          for (final ip in CcChannel._asList(m['ips']))
            if (ip != null && '$ip'.isNotEmpty) '$ip',
        ],
      );
}


class CcTailscaleUserGroup {
  const CcTailscaleUserGroup({
    this.userId = 0,
    this.loginName = '',
    this.displayName = '',
    this.peers = const [],
  });

  final int userId;
  final String loginName;
  final String displayName;
  final List<CcTailscalePeer> peers;


  String get title => displayName.isNotEmpty ? displayName : loginName;

  factory CcTailscaleUserGroup.fromMap(Map<String, dynamic> m) =>
      CcTailscaleUserGroup(
        userId: CcTailscalePeer._int(m['user_id']),
        loginName: '${m['login_name'] ?? ''}',
        displayName: '${m['display_name'] ?? ''}',
        peers: [
          for (final p in CcChannel._asList(m['peers']))
            if (p is Map) CcTailscalePeer.fromMap(CcChannel._asMap(p)),
        ],
      );
}



class CcTailscalePingResult {
  const CcTailscalePingResult({
    this.latencyMs = 0,
    this.isDirect = false,
    this.endpoint = '',
    this.derpRegionCode = '',
    this.error = '',
  });

  final double latencyMs;
  final bool isDirect;
  final String endpoint;
  final String derpRegionCode;
  final String error;

  factory CcTailscalePingResult.fromMap(Map<String, dynamic> m) =>
      CcTailscalePingResult(
        latencyMs: m['latency_ms'] is num
            ? (m['latency_ms'] as num).toDouble()
            : 0,
        isDirect: m['is_direct'] == true,
        endpoint: '${m['endpoint'] ?? ''}',
        derpRegionCode: '${m['derp_region_code'] ?? ''}',
        error: '${m['error'] ?? ''}',
      );
}



class CcStatus {
  const CcStatus({
    this.uplink = 0,
    this.downlink = 0,
    this.uplinkTotal = 0,
    this.downlinkTotal = 0,
    this.memory = 0,
    this.goroutines = 0,
    this.connectionsIn = 0,
    this.connectionsOut = 0,
  });

  final int uplink;
  final int downlink;
  final int uplinkTotal;
  final int downlinkTotal;
  final int memory;
  final int goroutines;
  final int connectionsIn;
  final int connectionsOut;



  int get connectionsTotal => connectionsIn + connectionsOut;

  factory CcStatus.fromMap(Map<String, dynamic> m) => CcStatus(
    uplink: _int(m['uplink']),
    downlink: _int(m['downlink']),
    uplinkTotal: _int(m['uplinkTotal']),
    downlinkTotal: _int(m['downlinkTotal']),
    memory: _int(m['memory']),
    goroutines: _int(m['goroutines']),
    connectionsIn: _int(m['connectionsIn']),
    connectionsOut: _int(m['connectionsOut']),
  );
}


class CcOutbound {
  const CcOutbound({
    required this.tag,
    required this.type,
    required this.urlTestDelay,
    required this.urlTestTime,
    this.endpointState = '',
    this.idleSinceSeconds = 0,
  });

  final String tag;
  final String type;


  final int urlTestDelay;


  final int urlTestTime;







  final String endpointState;


  final int idleSinceSeconds;

  factory CcOutbound.fromMap(Map<String, dynamic> m) => CcOutbound(
    tag: m['tag']?.toString() ?? '',
    type: m['type']?.toString() ?? '',
    urlTestDelay: _int(m['urlTestDelay']),
    urlTestTime: _int(m['urlTestTime']),

    endpointState: m['endpointState']?.toString() ?? '',
    idleSinceSeconds: _int(m['idleSinceSeconds']),
  );
}



abstract final class CcEndpointState {

  static const neverBuilt = 'never_built';


  static const building = 'building';


  static const up = 'up';


  static const asleep = 'asleep';


  static const tornDown = 'torn_down';


  static const down = 'down';



  static const disabled = 'disabled';



  static bool isNotBuilt(String s) => s == neverBuilt || s == tornDown;
}



class CcGroup {
  const CcGroup({
    required this.tag,
    required this.type,
    required this.selectable,
    required this.selected,
    required this.isExpand,
    required this.items,
  });

  final String tag;
  final String type;
  final bool selectable;
  final String selected;
  final bool isExpand;
  final List<CcOutbound> items;

  factory CcGroup.fromMap(Map<String, dynamic> m) => CcGroup(
    tag: m['tag']?.toString() ?? '',
    type: m['type']?.toString() ?? '',
    selectable: m['selectable'] == true,
    selected: m['selected']?.toString() ?? '',
    isExpand: m['isExpand'] == true,
    items: (m['items'] is List ? m['items'] as List : const [])
        .map((e) => CcOutbound.fromMap(CcChannel._asMap(e)))
        .toList(),
  );
}








class CcConnection {
  const CcConnection({
    required this.id,
    required this.network,
    required this.domain,
    required this.destination,
    required this.rule,
    required this.uplink,
    required this.downlink,
    this.uplinkDelta = 0,
    this.downlinkDelta = 0,
    this.outbound = '',
    this.outboundType = '',
    this.protocol = '',
    this.chains = const [],
    this.detours = const [],
    this.packageName = '',
    this.processPath = '',
    required this.createdAt,
    required this.closedAt,
  });

  final String id;
  final String network;
  final String domain;
  final String destination;
  final String rule;


  final int uplink;
  final int downlink;


  final int uplinkDelta;
  final int downlinkDelta;


  final String outbound;
  final String outboundType;
  final String protocol;



  final List<String> chains;





  final List<String> detours;


  final String packageName;
  final String processPath;

  final int createdAt;
  final int closedAt;

  bool get isClosed => closedAt > 0;



















  String routingLineOf({bool compact = false, String? ruleLabel}) {
    final sb = StringBuffer();

    final inner = <String>[];
    final ruleText = (ruleLabel != null && ruleLabel.isNotEmpty)
        ? ruleLabel
        : (rule.isNotEmpty ? rule : 'final');
    inner.add(
      !compact && network.isNotEmpty ? '[$network] $ruleText' : ruleText,
    );
    if (chains.length > 1) inner.addAll(chains.sublist(1).reversed);
    sb.write(inner.join(' ⇒ '));





    final phys = <String>[...foldSelectorPairs(detours).reversed];
    final exitChain = chains.isNotEmpty
        ? chains
        : (outbound.isNotEmpty ? [outbound] : null);
    if (exitChain != null) {
      var exit = exitChain.first;
      for (final sel in exitChain.skip(1)) {
        exit = '$sel ($exit)';
      }
      phys.add(exit);
    }
    final dest = domain.isNotEmpty ? domain : _hostOfDestination;
    if (dest.isNotEmpty) phys.add(dest);
    if (phys.isNotEmpty) sb.write(' : ${phys.join(' → ')}');
    return sb.toString();
  }


  String get _hostOfDestination {
    final d = destination;
    if (d.isEmpty) return '';
    if (d.startsWith('[')) {
      final end = d.indexOf(']');
      return end > 0 ? d.substring(0, end + 1) : d;
    }
    final colon = d.lastIndexOf(':');
    return colon > 0 ? d.substring(0, colon) : d;
  }

  factory CcConnection.fromMap(Map<String, dynamic> m) => CcConnection(
    id: m['id']?.toString() ?? '',
    network: m['network']?.toString() ?? '',
    domain: m['domain']?.toString() ?? '',
    destination: m['destination']?.toString() ?? '',
    rule: m['rule']?.toString() ?? '',
    uplink: _int(m['uplink']),
    downlink: _int(m['downlink']),
    uplinkDelta: _int(m['uplinkDelta']),
    downlinkDelta: _int(m['downlinkDelta']),
    outbound: m['outbound']?.toString() ?? '',
    outboundType: m['outboundType']?.toString() ?? '',
    protocol: m['protocol']?.toString() ?? '',
    chains:
        (m['chains'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    detours:
        (m['detours'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    packageName: m['packageName']?.toString() ?? '',
    processPath: m['processPath']?.toString() ?? '',
    createdAt: _int(m['createdAt']),
    closedAt: _int(m['closedAt']),
  );
}





class CcDnsQuery {
  const CcDnsQuery({
    required this.domain,
    required this.queryType,
    required this.rcode,
    this.ttl = 0,
    this.source = '',
    this.failed = false,
    this.error = '',
    this.packageName = '',
    this.processPath = '',
    this.dnsServer = '',
    this.dnsServerType = '',
    this.outbound = const [],
    this.answers = const [],
    this.groupPath = const [],
    this.attempts = const [],
    this.fanned = false,
    this.survival = false,
  });


  final String domain;


  final int queryType;




  final int rcode;

  final int ttl;


  final String source;



  final bool failed;


  final String error;



  final String packageName;
  final String processPath;



  final String dnsServer;


  final String dnsServerType;




  final List<String> outbound;




  final List<CcDnsAnswer> answers;



  final List<String> groupPath;





  final List<CcDnsGroupAttempt> attempts;



  final bool fanned;



  final bool survival;


  bool get noAnswer => rcode == -1;


  bool get viaGroup => groupPath.isNotEmpty;

  factory CcDnsQuery.fromMap(Map<String, dynamic> m) => CcDnsQuery(
    domain: m['domain']?.toString() ?? '',
    queryType: _int(m['queryType']),
    rcode: _int(m['rcode']),
    ttl: _int(m['ttl']),
    source: m['source']?.toString() ?? '',
    failed: m['failed'] == true,
    error: m['error']?.toString() ?? '',
    packageName: m['packageName']?.toString() ?? '',
    processPath: m['processPath']?.toString() ?? '',
    dnsServer: m['dnsServer']?.toString() ?? '',
    dnsServerType: m['dnsServerType']?.toString() ?? '',
    outbound:
        (m['outbound'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    answers:
        (m['answers'] as List?)
            ?.map(
              (a) => CcDnsAnswer.fromMap(
                (a as Map).map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList() ??
        const [],

    groupPath:
        (m['groupPath'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    attempts:
        (m['attempts'] as List?)
            ?.whereType<Map>()
            .map(
              (a) => CcDnsGroupAttempt.fromMap(
                a.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList() ??
        const [],
    fanned: m['fanned'] == true,
    survival: m['survival'] == true,
  );
}


class CcDnsGroupAttempt {
  const CcDnsGroupAttempt({
    required this.server,
    required this.serverType,
    required this.outcome,
    required this.rttMs,
  });


  final String server;


  final String serverType;


  final String outcome;


  final int rttMs;

  bool get answered => outcome == 'answered';

  factory CcDnsGroupAttempt.fromMap(Map<String, dynamic> m) =>
      CcDnsGroupAttempt(
        server: m['server']?.toString() ?? '',
        serverType: m['serverType']?.toString() ?? '',
        outcome: m['outcome']?.toString() ?? '',
        rttMs: _int(m['rttMs']),
      );
}


class CcDnsAnswer {
  const CcDnsAnswer({
    required this.name,
    required this.type,
    required this.rdata,
    this.ttl = 0,
  });

  final String name;
  final int type;
  final String rdata;
  final int ttl;

  bool get isCname => type == 5;
  bool get isAddress => type == 1 || type == 28;

  factory CcDnsAnswer.fromMap(Map<String, dynamic> m) => CcDnsAnswer(
    name: m['name']?.toString() ?? '',
    type: _int(m['type']),
    rdata: m['rdata']?.toString() ?? '',
    ttl: _int(m['ttl']),
  );
}


class CcDelayResult {
  const CcDelayResult({required this.delay, required this.error});

  final int delay;
  final String error;

  bool get ok => error.isEmpty;


  int get lastDelayValue => ok ? delay : -1;

  factory CcDelayResult.fromMap(Map<String, dynamic> m) => CcDelayResult(
    delay: _int(m['delay']),
    error: m['error']?.toString() ?? '',
  );
}













class CcGetUrlResult {
  const CcGetUrlResult({
    required this.status,
    required this.content,
    required this.truncated,
    required this.contentType,
    required this.remoteAddr,
    required this.elapsedMs,
    required this.error,
  });

  final int status;
  final String content;
  final bool truncated;
  final String contentType;
  final String remoteAddr;
  final int elapsedMs;
  final String error;


  bool get ok => error.isEmpty;

  factory CcGetUrlResult.fromMap(Map<String, dynamic> m) => CcGetUrlResult(
    status: _int(m['status']),
    content: m['content']?.toString() ?? '',
    truncated: m['truncated'] == true,
    contentType: m['contentType']?.toString() ?? '',
    remoteAddr: m['remoteAddr']?.toString() ?? '',
    elapsedMs: _int(m['elapsedMs']),
    error: m['error']?.toString() ?? '',
  );
}




class CcPoolSlot {
  const CcPoolSlot({
    required this.slot,
    required this.tag,
    required this.delay,
  });

  final int slot;
  final String tag;
  final int delay;


  bool get alive => delay > 0;

  factory CcPoolSlot.fromMap(Map<String, dynamic> m) => CcPoolSlot(
    slot: _int(m['slot']),
    tag: m['tag']?.toString() ?? '',
    delay: _int(m['delay']),
  );
}


class CcDnsGroupMember {
  const CcDnsGroupMember({
    required this.tag,
    required this.serverType,
    required this.clean,
    required this.liveErrors,
    required this.lastErrorAgeMs,
    required this.liveWins,
    required this.current,
    required this.lastRttMs,
  });

  final String tag;
  final String serverType;
  final bool clean;
  final int liveErrors;
  final int lastErrorAgeMs;
  final int liveWins;
  final bool current;
  final int lastRttMs;

  factory CcDnsGroupMember.fromMap(Map<String, dynamic> m) => CcDnsGroupMember(
    tag: m['tag']?.toString() ?? '',
    serverType: m['serverType']?.toString() ?? '',
    clean: m['clean'] == true,
    liveErrors: _int(m['liveErrors']),
    lastErrorAgeMs: _int(m['lastErrorAgeMs'], fallback: -1),
    liveWins: _int(m['liveWins']),
    current: m['current'] == true,
    lastRttMs: _int(m['lastRttMs']),
  );
}


class CcDnsGroup {
  const CcDnsGroup({
    required this.tag,
    required this.mode,
    required this.current,
    required this.members,
  });

  final String tag;
  final String mode;
  final String current;
  final List<CcDnsGroupMember> members;

  factory CcDnsGroup.fromMap(Map<String, dynamic> m) => CcDnsGroup(
    tag: m['tag']?.toString() ?? '',
    mode: m['mode']?.toString() ?? '',
    current: m['current']?.toString() ?? '',
    members: [
      for (final e in (m['members'] as List<dynamic>? ?? const []))
        if (e is Map) CcDnsGroupMember.fromMap(CcChannel._asMap(e)),
    ],
  );
}


class CcRule {
  const CcRule({
    required this.type,
    required this.payload,
    required this.action,
    required this.isDNS,
  });

  final String type;
  final String payload;
  final String action;
  final bool isDNS;

  factory CcRule.fromMap(Map<String, dynamic> m) => CcRule(
    type: m['type']?.toString() ?? '',
    payload: m['payload']?.toString() ?? '',
    action: m['action']?.toString() ?? '',
    isDNS: m['isDNS'] == true,
  );
}

int _int(Object? v, {int fallback = 0}) =>
    v is int ? v : (v is num ? v.toInt() : fallback);
