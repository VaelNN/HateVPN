using System.Text.Json;
using System.Text.RegularExpressions;

namespace HateVPN.Core;

public sealed record Invitation(string Id, string Name, AmneziaWgConfig Config);

public static class InvitationLink
{
    private const string Prefix = "hatevpn://invite/";
    private sealed record Payload(int Version, string Id, string Name, string Config);

    public static string Create(string id, string name, string config)
    {
        if (!Regex.IsMatch(id, "^hv-[0-9a-f]{32}$")) throw new FormatException("Некорректный номер приглашения.");
        name = CleanName(name);
        var parsed = AmneziaWgConfig.Parse(config);
        if (!parsed.FullTunnel) throw new FormatException("Приглашение должно направлять весь трафик через VPN.");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new Payload(1, id, name, parsed.Text));
        return Prefix + Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public static Invitation Parse(string link)
    {
        link = link.Trim();
        if (!link.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) || link.Length > 60000)
            throw new FormatException("Вставьте ссылку приглашения HateVPN.");
        var encoded = link[Prefix.Length..];
        if (encoded.Length == 0 || !Regex.IsMatch(encoded, "^[A-Za-z0-9_-]+$"))
            throw new FormatException("Ссылка приглашения повреждена.");
        try
        {
            var raw = encoded.Replace('-', '+').Replace('_', '/');
            raw = raw.PadRight((raw.Length + 3) / 4 * 4, '=');
            var payload = JsonSerializer.Deserialize<Payload>(Convert.FromBase64String(raw))
                ?? throw new FormatException();
            if (payload.Version != 1 || !Regex.IsMatch(payload.Id ?? "", "^hv-[0-9a-f]{32}$")) throw new FormatException();
            var name = CleanName(payload.Name);
            var config = AmneziaWgConfig.Parse(payload.Config);
            if (!config.FullTunnel) throw new FormatException();
            return new Invitation(payload.Id!, name, config);
        }
        catch { throw new FormatException("Ссылка приглашения повреждена или не поддерживается."); }
    }

    private static string CleanName(string? name)
    {
        name = new string((name ?? "").Trim().Where(c => !char.IsControl(c)).Take(48).ToArray());
        if (string.IsNullOrWhiteSpace(name)) throw new FormatException("Укажите имя друга.");
        return name;
    }
}
