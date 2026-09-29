








class DiagnosticCheck {
  const DiagnosticCheck({
    required this.id,
    required this.title,
    required this.url,
  });


  final String id;


  final String title;

  final String url;
}











const List<DiagnosticCheck> kDiagnosticChecks = [
  DiagnosticCheck(
    id: 'cf_trace',
    title: 'Cloudflare trace',
    url: 'https://1.1.1.1/cdn-cgi/trace',
  ),
  DiagnosticCheck(
    id: 'cf_trace_host',
    title: 'Cloudflare trace (hostname)',
    url: 'https://cloudflare.com/cdn-cgi/trace',
  ),
  DiagnosticCheck(
    id: 'ip2location',
    title: 'IP & location',
    url: 'https://api.ip2location.io/',
  ),
  DiagnosticCheck(
    id: 'ipinfo',
    title: 'IP info',
    url: 'https://ipinfo.io/json',
  ),
];
