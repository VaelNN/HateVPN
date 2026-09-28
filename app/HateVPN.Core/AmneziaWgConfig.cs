using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace HateVPN.Core;

public sealed record AmneziaWgConfig(string Text, string Endpoint, bool FullTunnel)
{
    private static readonly string[] OrderedParameters =
    [
        "Jc", "Jmin", "Jmax", "S1", "S2", "S3", "S4",
        "H1", "H2", "H3", "H4", "I1", "I2", "I3", "I4", "I5",
        "J1", "J2", "J3", "ITime",
        "HeaderProtectionKey", "ContentPaddingAddition", "RekeyAfterTime",
        "RekeyTimeout", "RejectAfterTime", "KeepaliveTimeout",
        "MaxHandshakeAttempts", "RandomTrailers", "DisableCookies"
    ];
    private static readonly HashSet<string> Parameters = new(OrderedParameters, StringComparer.OrdinalIgnoreCase);
    private static readonly HashSet<string> OptionalEmpty = new(
        ["I1", "I2", "I3", "I4", "I5", "J1", "J2", "J3", "ITime", "HeaderProtectionKey", "ContentPaddingAddition",
         "RekeyAfterTime", "RekeyTimeout", "RejectAfterTime", "KeepaliveTimeout",
         "MaxHandshakeAttempts", "RandomTrailers", "DisableCookies"], StringComparer.OrdinalIgnoreCase);

    public static bool IsAmnezia(string text) =>
        Regex.IsMatch(text, @"(?im)^\s*(?:Jc|Jmin|Jmax|S[1-4]|H[1-4]|I[1-5]|J[1-3]|ITime|HeaderProtectionKey|ContentPaddingAddition|RekeyAfterTime|RekeyTimeout|RejectAfterTime|KeepaliveTimeout|MaxHandshakeAttempts|RandomTrailers|DisableCookies)\s*=");

    public static AmneziaWgConfig Parse(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > 32768) throw new FormatException("Файл конфигурации слишком большой.");
        var extras = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var ordinary = new StringBuilder();
        var section = "";
        string? keepaliveRange = null;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.Split('#')[0].Trim();
            if (line.Equals("[Interface]", StringComparison.OrdinalIgnoreCase)) section = "interface";
            else if (line.Equals("[Peer]", StringComparison.OrdinalIgnoreCase)) section = "peer";
            var match = Regex.Match(line, @"^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)$");
            if (match.Success && Parameters.Contains(match.Groups[1].Value))
            {
                var key = OrderedParameters.First(p => p.Equals(match.Groups[1].Value, StringComparison.OrdinalIgnoreCase));
                var value = match.Groups[2].Value.Trim();
                if (section != "interface" || !extras.TryAdd(key, value))
                    throw new FormatException("Некорректные или повторяющиеся параметры AmneziaWG.");
                continue;
            }
            if (section == "peer" && match.Success &&
                match.Groups[1].Value.Equals("PersistentKeepalive", StringComparison.OrdinalIgnoreCase) &&
                match.Groups[2].Value.Contains('-'))
            {
                if (keepaliveRange is not null) throw new FormatException("Повторяющийся PersistentKeepalive.");
                keepaliveRange = match.Groups[2].Value.Trim();
                CheckRange(keepaliveRange, 0, 65535, "PersistentKeepalive");
                ordinary.AppendLine("PersistentKeepalive = 25");
                continue;
            }
            ordinary.AppendLine(raw.TrimEnd('\r'));
        }
        if (extras.Count == 0) throw new FormatException("Профиль не содержит параметров AmneziaWG.");
        Validate(extras);
        var baseConfig = WireGuardConfig.Parse(ordinary.ToString());
        var insertion = new StringBuilder();
        foreach (var key in OrderedParameters)
            if (extras.TryGetValue(key, out var value) && value.Length > 0)
                insertion.AppendLine($"{key} = {value}");
        var marker = "\n[Peer]";
        var index = baseConfig.Text.IndexOf(marker, StringComparison.Ordinal);
        var normalized = baseConfig.Text.Insert(index, insertion.ToString());
        if (keepaliveRange is not null)
            normalized = normalized.Replace("PersistentKeepalive = 25", "PersistentKeepalive = " + keepaliveRange, StringComparison.Ordinal);
        return new(normalized, baseConfig.Endpoint, baseConfig.FullTunnel);
    }

    private static void Validate(Dictionary<string, string> extras)
    {
        foreach (var (key, value) in extras)
        {
            if (value.Length == 0)
            {
                if (!OptionalEmpty.Contains(key)) throw new FormatException($"Пустой параметр {key}.");
                continue;
            }
            if (value.Length > 512 || value.Any(char.IsControl))
                throw new FormatException($"Некорректный параметр {key}.");
            if (key.Equals("HeaderProtectionKey", StringComparison.OrdinalIgnoreCase))
            {
                try { if (Convert.FromBase64String(value).Length != 32) throw new FormatException(); }
                catch { throw new FormatException("Некорректный HeaderProtectionKey."); }
            }
            else if (key is "RandomTrailers" or "DisableCookies")
            {
                if (!new[] { "on", "off", "true", "false", "1", "0" }.Contains(value, StringComparer.OrdinalIgnoreCase))
                    throw new FormatException($"Некорректный параметр {key}.");
            }
            else if (key is "Jc" or "Jmin" or "Jmax" or "S1" or "S2" or "S3" or "S4" or
                     "ContentPaddingAddition" or "RekeyAfterTime" or "RekeyTimeout" or "RejectAfterTime" or
                     "KeepaliveTimeout" or "MaxHandshakeAttempts")
                CheckRange(value, 0, 65535, key);
            else if (key is "H1" or "H2" or "H3" or "H4")
                CheckRange(value, 1, uint.MaxValue, key);
        }
        if (extras.TryGetValue("Jc", out var jc) && !jc.Contains('-') &&
            (ushort.Parse(jc, CultureInfo.InvariantCulture) is < 1 or > 128))
            throw new FormatException("Jc должен быть от 1 до 128.");
        if (extras.TryGetValue("Jmin", out var min) && extras.TryGetValue("Jmax", out var max) &&
            !min.Contains('-') && !max.Contains('-') &&
            ushort.Parse(min, CultureInfo.InvariantCulture) >= ushort.Parse(max, CultureInfo.InvariantCulture))
            throw new FormatException("Jmax должен быть больше Jmin.");
        if (extras.TryGetValue("S1", out var s1) && extras.TryGetValue("S2", out var s2) &&
            !s1.Contains('-') && !s2.Contains('-') &&
            ushort.Parse(s1, CultureInfo.InvariantCulture) + 56 == ushort.Parse(s2, CultureInfo.InvariantCulture))
            throw new FormatException("S1 и S2 несовместимы.");
        var fixedHeaders = new[] { "H1", "H2", "H3", "H4" }
            .Where(extras.ContainsKey).Select(key => extras[key]).Where(value => !value.Contains('-')).ToArray();
        if (fixedHeaders.Distinct().Count() != fixedHeaders.Length)
            throw new FormatException("H1–H4 должны различаться.");
    }

    private static void CheckRange(string value, uint min, uint max, string key)
    {
        var parts = value.Split('-', 2);
        if (!uint.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var first) ||
            first < min || first > max ||
            parts.Length == 2 && (!uint.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var last) ||
                                  last < first || last > max))
            throw new FormatException($"Некорректное значение {key}.");
    }
}
