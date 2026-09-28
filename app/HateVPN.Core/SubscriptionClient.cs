using System.Net.Http.Headers;
using System.Text;

namespace HateVPN.Core;

public static class SubscriptionClient
{
    public static async Task<IReadOnlyList<XrayNode>> FetchAsync(string url, string deviceId, CancellationToken token = default)
    {
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.UserInfo.Length != 0 || url.Length > 2048)
            throw new FormatException("Введите HTTPS-ссылку подписки.");
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.UserAgent.Add(new ProductInfoHeaderValue("HateVPN", "0.4"));
        request.Headers.TryAddWithoutValidation("x-hwid", deviceId);
        request.Headers.TryAddWithoutValidation("x-device-os", "Windows");
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        if (response.RequestMessage?.RequestUri?.Scheme != Uri.UriSchemeHttps)
            throw new FormatException("Подписка перенаправила на незащищённый адрес.");
        if (response.Content.Headers.ContentLength > 262144) throw new FormatException("Подписка слишком большая.");
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(chunk, token)) > 0)
        {
            if (buffer.Length + count > 262144) throw new FormatException("Подписка слишком большая.");
            buffer.Write(chunk, 0, count);
        }
        var text = Encoding.UTF8.GetString(buffer.ToArray()).Trim();
        if (!text.Contains("://", StringComparison.Ordinal))
        {
            try {
                var compact = new string(text.Where(c => !char.IsWhiteSpace(c)).ToArray());
                text = Encoding.UTF8.GetString(Convert.FromBase64String(compact));
            } catch (FormatException) { throw new FormatException("Не удалось прочитать подписку."); }
        }
        var nodes = new List<XrayNode>();
        foreach (var line in text.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            if (!line.StartsWith("vless://", StringComparison.OrdinalIgnoreCase)) continue;
            try { nodes.Add(XrayNode.Parse(line)); }
            catch (FormatException) { }
        }
        if (nodes.Count == 0) throw new FormatException(text.Contains("App not supported",StringComparison.OrdinalIgnoreCase)
            ? "Провайдер не разрешил загрузить подписку для этого устройства. Проверьте лимит устройств."
            : "В подписке нет поддерживаемых серверов VLESS/REALITY.");
        return nodes;
    }
}
