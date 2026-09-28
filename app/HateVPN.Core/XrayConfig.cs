using System.Text.Json;

namespace HateVPN.Core;

public sealed record XrayNode(string Link, string Name, string Endpoint, string Host, int Port,
    string Id, string Network, string Flow, string ServerName, string Fingerprint,
    string PublicKey, string ShortId, string ServiceName, bool MultiMode)
{
    public static XrayNode Parse(string link)
    {
        if (link.Length > 8192 || !Uri.TryCreate(link, UriKind.Absolute, out var uri) || uri.Scheme != "vless" ||
            uri.Port is < 1 or > 65535 || uri.Host is "0.0.0.0" or "127.0.0.1" ||
            !Guid.TryParse(uri.UserInfo, out _))
            throw new FormatException("Нужна рабочая ссылка VLESS из подписки.");
        var query = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach (var pair in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            var key = Uri.UnescapeDataString(parts[0].Replace('+',' '));
            var value = Uri.UnescapeDataString((parts.Length == 2 ? parts[1] : "").Replace('+',' '));
            if (!query.TryAdd(key,value)) throw new FormatException("Повторяющийся параметр VLESS.");
        }
        string Get(string key) => query.GetValueOrDefault(key) ?? "";
        var network = Get("type") is "tcp" or "raw" ? "raw" : Get("type");
        if (Get("security") != "reality" || Get("encryption") != "none" || network is not ("raw" or "grpc") ||
            string.IsNullOrWhiteSpace(Get("sni")) || string.IsNullOrWhiteSpace(Get("pbk")))
            throw new FormatException("Поддерживается VLESS с REALITY через TCP или gRPC.");
        if (network == "raw" && Get("flow") is not ("" or "xtls-rprx-vision" or "xtls-rprx-vision-udp443"))
            throw new FormatException("Неподдерживаемый режим VLESS.");
        var name = Uri.UnescapeDataString(uri.Fragment.TrimStart('#'));
        name = new string(name.Where(c => !char.IsControl(c)).Take(48).ToArray());
        if (string.IsNullOrWhiteSpace(name)) name = uri.Host;
        return new(link, name, $"{uri.Host}:{uri.Port}", uri.Host, uri.Port, uri.UserInfo,
            network, Get("flow"), Get("sni"), Get("fp") is { Length: > 0 } fp ? fp : "chrome",
            Get("pbk"), Get("sid"), Get("serviceName"), Get("mode") == "multi");
    }

    public string Build(bool tunnel = true)
    {
        var stream = new Dictionary<string,object> {
            ["network"] = Network, ["security"] = "reality",
            ["realitySettings"] = new { serverName = ServerName, fingerprint = Fingerprint, password = PublicKey, shortId = ShortId }
        };
        if (Network == "grpc") stream["grpcSettings"] = new { serviceName = ServiceName, multiMode = MultiMode };
        var inbounds = new List<object> {
            new { tag = "local-socks", listen = "127.0.0.1", port = 29451, protocol = "socks", settings = new { udp = true } },
            new { tag = "local-http", listen = "127.0.0.1", port = 29452, protocol = "http" }
        };
        if (tunnel) inbounds.Add(new { tag = "system-tun", protocol = "tun", settings = new {
            name = "HateVPN", desc = "HateVPN", mtu = 1280,
            gateway = new[]{"10.88.0.1/30", "fc00::1/64"}, dns = new[]{"1.1.1.1"},
            autoSystemRoutingTable = new[]{"0.0.0.0/0", "::/0"}, autoOutboundsInterface = "auto"
        }});
        var config = new {
            log = new { loglevel = "warning" },
            inbounds,
            outbounds = new object[] {
                new { tag = "proxy", protocol = "vless", settings = new {
                    address = Host, port = Port, id = Id, encryption = "none", flow = Flow
                }, streamSettings = stream },
                new { tag = "direct", protocol = "freedom" }
            }
        };
        return JsonSerializer.Serialize(config);
    }
}
