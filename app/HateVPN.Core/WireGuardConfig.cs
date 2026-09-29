using System.Globalization;
using System.Net;
using System.Text;

namespace HateVPN.Core;

public sealed record WireGuardConfig(string Text, string Endpoint, bool FullTunnel)
{
    public static WireGuardConfig Parse(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > 32768) throw new FormatException("Файл конфигурации слишком большой.");
        var iface = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var peer = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, string>? section = null;
        var seenInterface = false; var seenPeer = false;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Split('#')[0].Trim();
            if (line.Length == 0) continue;
            if (line.Equals("[Interface]", StringComparison.OrdinalIgnoreCase) && !seenInterface)
            { seenInterface = true; section = iface; continue; }
            if (line.Equals("[Peer]", StringComparison.OrdinalIgnoreCase) && !seenPeer)
            { seenPeer = true; section = peer; continue; }
            var equals = line.IndexOf('=');
            if (section is null || equals < 1 || line.StartsWith('[')) throw new FormatException("Нужен клиентский профиль WireGuard с одним сервером.");
            var key = line[..equals].Trim(); var value = line[(equals + 1)..].Trim();
            string[] allowed = section == iface ? ["PrivateKey", "Address", "DNS", "MTU", "ListenPort"] : ["PublicKey", "PresharedKey", "Endpoint", "AllowedIPs", "PersistentKeepalive"];
            var canonical = allowed.FirstOrDefault(k => k.Equals(key, StringComparison.OrdinalIgnoreCase));
            if (canonical is null) throw new FormatException("В профиле есть неподдерживаемые параметры. Нужен обычный WireGuard без скриптов и расширений AmneziaWG.");
            if (value.Length == 0 || value.Any(char.IsControl) || !section.TryAdd(canonical, value)) throw new FormatException("Пустой или повторяющийся параметр конфигурации.");
        }
        string Required(Dictionary<string,string> map, string key) => map.TryGetValue(key, out var v) ? v : throw new FormatException($"В профиле отсутствует {key}.");
        CheckKey(Required(iface, "PrivateKey")); CheckKey(Required(peer, "PublicKey"));
        if (peer.TryGetValue("PresharedKey", out var psk)) CheckKey(psk);
        CheckCidrs(Required(iface,"Address")); CheckCidrs(Required(peer,"AllowedIPs"));
        foreach (var dns in Required(iface,"DNS").Split(',')) if (!IPAddress.TryParse(dns.Trim(),out _)) throw new FormatException("DNS должен содержать IP-адреса.");
        var endpoint = Required(peer,"Endpoint");
        if (!Uri.TryCreate("udp://" + endpoint, UriKind.Absolute, out var uri) || uri.Port < 1 || uri.Port > 65535 || uri.UserInfo.Length != 0 || uri.AbsolutePath != "/" || uri.Query.Length != 0 || uri.Fragment.Length != 0 || Uri.CheckHostName(uri.Host.Trim('[',']')) == UriHostNameType.Unknown)
            throw new FormatException("Некорректный адрес сервера. Ожидается адрес:порт.");
        CheckNumber(iface,"MTU", 576, 9000); CheckNumber(iface,"ListenPort",0,65535); CheckNumber(peer,"PersistentKeepalive",0,65535);
        var routes = peer["AllowedIPs"].Split(',').Select(x=>x.Trim()).ToList();
        var full = routes.Contains("0.0.0.0/0");

        if (full && !routes.Contains("::/0")) { routes.Add("::/0"); peer["AllowedIPs"] = string.Join(", ",routes); }
        if (!peer.ContainsKey("PersistentKeepalive")) peer["PersistentKeepalive"] = "25";
        var normalized = new StringBuilder("[Interface]\n");
        foreach (var kv in iface) normalized.AppendLine($"{kv.Key} = {kv.Value}");
        normalized.AppendLine("\n[Peer]");
        foreach (var kv in peer) normalized.AppendLine($"{kv.Key} = {kv.Value}");
        return new(normalized.ToString(), endpoint, full);
    }

    private static void CheckKey(string value)
    {
        byte[] bytes;
        try { bytes=Convert.FromBase64String(value); } catch { throw new FormatException("Некорректный ключ WireGuard."); }
        if (bytes.Length != 32 || bytes.All(b=>b==0)) throw new FormatException("Некорректный ключ WireGuard.");
    }
    private static void CheckCidrs(string value)
    {
        foreach(var item in value.Split(','))
        {
            var parts=item.Trim().Split('/');
            if(parts.Length!=2 || !IPAddress.TryParse(parts[0],out var ip) || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture,out var bits) || bits<0 || bits>ip.GetAddressBytes().Length*8)
                throw new FormatException("Некорректный IP-адрес или маска сети.");
        }
    }
    private static void CheckNumber(Dictionary<string,string> map,string key,int min,int max)
    {
        if(map.TryGetValue(key,out var value) && (!int.TryParse(value,NumberStyles.None,CultureInfo.InvariantCulture,out var n)|| n<min||n>max)) throw new FormatException($"Некорректное значение {key}.");
    }
}
