import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/dns/tailscale_endpoint_options.dart'
    show TailscaleEndpointOption;
import '../edit_controller.dart';
import '../../../services/l10n/locale_controller.dart';

















class ServerFormSection extends StatelessWidget {
  const ServerFormSection({super.key, required this.c});

  final DnsServerEditController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mode = c.serverMode;

    if (mode == null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.data_object, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                getLocalText.s(
                  "Custom server type \"%s\" — edit it on the JSON tab. The form supports UDP / DoT / DoH / DoQ / DoH3 / Group / Tailscale.",
                  c.rawServerType,
                ),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),



        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 520) {
              return DropdownButtonFormField<String>(
                key: ValueKey('dns-mode-$mode'),
                initialValue: mode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: getLocalText.s("Server type"),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [

                  const DropdownMenuItem(value: 'udp', child: Text('UDP')),

                  const DropdownMenuItem(value: 'tls', child: Text('DoT')),

                  const DropdownMenuItem(value: 'https', child: Text('DoH')),

                  const DropdownMenuItem(value: 'quic', child: Text('DoQ')),

                  const DropdownMenuItem(value: 'h3', child: Text('DoH3')),
                  DropdownMenuItem(
                    value: 'group',
                    child: Text(getLocalText.s("Group")),
                  ),
                  const DropdownMenuItem(
                    value: 'tailscale',
                    child: Text('Tailscale'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) c.setServerMode(v);
                },
              );
            }
            return SegmentedButton<String>(
              segments: [

                const ButtonSegment(value: 'udp', label: Text('UDP')),

                const ButtonSegment(value: 'tls', label: Text('DoT')),

                const ButtonSegment(value: 'https', label: Text('DoH')),

                const ButtonSegment(value: 'quic', label: Text('DoQ')),

                const ButtonSegment(value: 'h3', label: Text('DoH3')),
                ButtonSegment(
                  value: 'group',
                  label: Text(getLocalText.s("Group")),
                ),
                const ButtonSegment(
                  value: 'tailscale',
                  label: Text('Tailscale'),
                ),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => c.setServerMode(s.first),
            );
          },
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(switch (mode) {
            'tls' => getLocalText.s("DNS-over-TLS · port 853"),
            'https' => getLocalText.s("DNS-over-HTTPS · port 443"),
            'quic' => getLocalText.s("DNS-over-QUIC · port 853"),
            'h3' => getLocalText.s("DNS-over-HTTP/3 · port 443"),
            'group' => getLocalText.s(
              "Several servers behind one tag — survives a member failure",
            ),
            'tailscale' => getLocalText.s(
              "MagicDNS of the tailnet via a Tailscale node · no address",
            ),
            _ => getLocalText.s("Plain UDP · port 53 · fast, unencrypted"),
          }, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        if (mode == 'group') ...[
          _GroupSection(c: c),
        ] else if (mode == 'tailscale') ...[
          _TailscaleSection(c: c),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: c.addressCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: getLocalText.s("Server address"),
                    hintText: kDnsPathModes.contains(mode)
                        ? getLocalText.s(
                            "192.168.1.1 / dns.example.com / https://… URL",
                          )
                        : getLocalText.s("192.168.1.1 / dns.example.com"),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: c.onAddressChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: c.portCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: getLocalText.s("Port"),
                    hintText: '${defaultDnsPort(mode)}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: c.onPortChanged,
                ),
              ),
            ],
          ),
          if (kDnsPathModes.contains(mode)) ...[
            const SizedBox(height: 12),
            TextField(
              controller: c.pathCtrl,
              decoration: InputDecoration(
                labelText: getLocalText.s("Path"),

                hintText: '/dns-query',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: c.onPathChanged,
            ),
          ],
          if (mode != 'udp') ...[
            const SizedBox(height: 12),
            TextField(
              controller: c.sniCtrl,
              decoration: InputDecoration(
                labelText: getLocalText.s("TLS server name (SNI) — optional"),
                hintText: getLocalText.s(
                  "dns.example.com — needed when address is an IP",
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: c.onSniChanged,
            ),
          ],
          if (c.isHostnameAddress) ...[
            const SizedBox(height: 12),
            _DomainResolverPicker(c: c),
          ],
        ],
      ],
    );
  }
}


class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.c});
  final DnsServerEditController c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final members = c.groupMembers;
    final self = c.tagCtrl.text.trim();
    final options = [
      for (final o in c.dnsMemberOptions)
        if (o.tag != self) o,
    ];


    final unknownMembers = [
      for (final m in members)
        if (!options.any((o) => o.tag == m)) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          getLocalText.s("Members"),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        if (options.isEmpty && unknownMembers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              getLocalText.s("No other DNS servers to add — create them first"),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        for (final o in options)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: members.contains(o.tag),
            onChanged: (v) => c.toggleGroupMember(o.tag, v == true),
            title: Text(
              o.tag,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
            subtitle: o.enabled

                ? Text(o.type, style: const TextStyle(fontSize: 11))
                : Text(
                    getLocalText.s("%s · disabled — will be skipped", o.type),
                    style: TextStyle(fontSize: 11, color: cs.error),
                  ),
          ),
        for (final m in unknownMembers)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: true,
            onChanged: (_) => c.toggleGroupMember(m, false),
            title: Text(
              m,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
            subtitle: Text(
              getLocalText.s("unknown server — will be skipped"),
              style: TextStyle(fontSize: 11, color: cs.error),
            ),
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('dns-group-mode-${c.groupMode}'),
          initialValue: c.groupMode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: getLocalText.s("Selection mode"),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: 'stable',
              child: Text(
                getLocalText.s("Stable — stick to one until it fails"),
              ),
            ),
            DropdownMenuItem(
              value: 'fastest',
              child: Text(
                getLocalText.s("Fastest — race, then stick to the winner"),
              ),
            ),
            DropdownMenuItem(
              value: 'parallel',
              child: Text(getLocalText.s("Parallel — race every query")),
            ),
          ],
          onChanged: (v) {
            if (v != null) c.setGroupMode(v);
          },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: c.errorTtlCtrl,
                decoration: InputDecoration(
                  labelText: getLocalText.s("Error TTL"),

                  hintText: '2m',
                  errorText: c.groupErrorTtlInvalid
                      ? getLocalText.s("Invalid duration (e.g. 2m, 90s)")
                      : null,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: c.onErrorTtlChanged,
              ),
            ),
            if (c.groupMode == 'fastest') ...[
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: c.winTtlCtrl,
                  decoration: InputDecoration(
                    labelText: getLocalText.s("Win TTL"),

                    hintText: '5m',
                    errorText: c.groupWinTtlInvalid
                        ? getLocalText.s("Invalid duration (e.g. 2m, 90s)")
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: c.onWinTtlChanged,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}






class _TailscaleSection extends StatelessWidget {
  const _TailscaleSection({required this.c});
  final DnsServerEditController c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = c.tailscaleEndpoint;
    final known = c.tailscaleEndpoints;
    final options = [
      if (current.isNotEmpty && !known.any((o) => o.tag == current))
        TailscaleEndpointOption(tag: current, enabled: true),
      ...known,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              getLocalText.s("No Tailscale nodes yet — add one on the Servers screen first"),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          )
        else
          DropdownButtonFormField<String>(


            key: ValueKey('dns-ts-endpoint-$current'),
            initialValue: current.isEmpty ? null : current,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: getLocalText.s("Tailscale node"),
              helperText: getLocalText.s("Which node's tailnet answers the queries"),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final o in options)
                DropdownMenuItem(
                  value: o.tag,
                  child: Text(
                    o.enabled
                        ? o.tag


                        : getLocalText.s("%s · disabled — will be skipped", o.tag),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: o.enabled ? null : cs.error,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) c.setTailscaleEndpoint(v);
            },
          ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(getLocalText.s("Accept default resolvers")),
          subtitle: Text(
            getLocalText.s("Names outside the tailnet go to the default DNS servers; off — NXDOMAIN"),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          value: c.acceptDefaultResolvers,
          onChanged: c.setAcceptDefaultResolvers,
        ),
      ],
    );
  }
}



class _DomainResolverPicker extends StatelessWidget {
  const _DomainResolverPicker({required this.c});
  final DnsServerEditController c;

  @override
  Widget build(BuildContext context) {
    final current = c.domainResolver;
    final tags = c.dnsServerTags.contains(current) || current.isEmpty
        ? c.dnsServerTags
        : [current, ...c.dnsServerTags];
    return DropdownButtonFormField<String>(


      key: ValueKey('dns-domres-$current'),
      initialValue: tags.contains(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: getLocalText.s("Domain resolver"),
        helperText: getLocalText.s("Resolves the server hostname itself"),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: tags
          .map(
            (t) => DropdownMenuItem(
              value: t,
              child: Text(
                t,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) c.setDomainResolver(v);
      },
    );
  }
}
