using System.Text.Json;
using System.Text.RegularExpressions;

namespace HateVPN.Core;

public sealed record OneTimeInvitation(string Id, string Name, string Host, int Port, string CertificateSha256, string Token);

public static class OneTimeInvitationLink
{
    private const string Prefix = "hatevpn://claim/";
    private sealed record Payload(int Version, string Id, string Name, string Host, int Port, string CertificateSha256, string Token);

    public static string Create(string id, string name, string host, int port, string certificateSha256, string token)
    {
        Validate(id, name, host, port, certificateSha256, token);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new Payload(1, id, name, host, port, certificateSha256, token));
        return Prefix + Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public static OneTimeInvitation Parse(string link)
    {
        link = link.Trim();
        if (!link.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) || link.Length > 4096)
            throw new FormatException("Вставьте одноразовую ссылку приглашения HateVPN.");
        var encoded = link[Prefix.Length..];
        if (encoded.Length == 0 || !Regex.IsMatch(encoded, "^[A-Za-z0-9_-]+$"))
            throw new FormatException("Ссылка приглашения повреждена.");
        try
        {
            var raw = encoded.Replace('-', '+').Replace('_', '/');
            raw = raw.PadRight((raw.Length + 3) / 4 * 4, '=');
            var payload = JsonSerializer.Deserialize<Payload>(Convert.FromBase64String(raw)) ?? throw new FormatException();
            if (payload.Version != 1) throw new FormatException();
            Validate(payload.Id, payload.Name, payload.Host, payload.Port, payload.CertificateSha256, payload.Token);
            return new(payload.Id, payload.Name, payload.Host, payload.Port, payload.CertificateSha256, payload.Token);
        }
        catch { throw new FormatException("Ссылка приглашения повреждена или не поддерживается."); }
    }

    private static void Validate(string id, string name, string host, int port, string fingerprint, string token)
    {
        if (!Regex.IsMatch(id ?? "", "^hv-[0-9a-f]{32}$") || string.IsNullOrWhiteSpace(name) || name.Length > 48 || name!.Any(char.IsControl) ||
            string.IsNullOrWhiteSpace(host) || !Regex.IsMatch(host, @"^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$") || host.Contains("..") ||
            port is < 1 or > 65535 || !Regex.IsMatch(fingerprint ?? "", "^[0-9a-f]{64}$") ||
            !Regex.IsMatch(token ?? "", "^[0-9a-f]{64}$"))
            throw new FormatException("Параметры приглашения повреждены.");
    }
}
