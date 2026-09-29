part of '../traffic_profiler.dart';










class _ConnSnapshot {
  _ConnSnapshot({
    required this.id,
    required this.host,
    required this.ip,
    required this.port,
    required this.network,
    required this.chains,
    required this.detours,
    this.outboundType,
    required this.upBytes,
    required this.downBytes,
    required this.startedAt,
    required this.process,
    required this.confidence,
    required this.matchedVia,
    required this.rule,
    required this.rulePayload,
  });
  final String id;
  final String host;
  final String ip;
  final int port;
  final String network;
  final List<String> chains;
  final List<String> detours;
  final String? outboundType;
  int upBytes;
  int downBytes;
  final DateTime startedAt;




  DateTime? kernelClosedAt;
  final String process;
  final ConfidenceLevel confidence;
  final String? matchedVia;
  final String rule;
  final String rulePayload;
}
