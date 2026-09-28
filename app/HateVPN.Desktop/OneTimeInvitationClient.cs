using HateVPN.Core;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace HateVPN.Desktop;

internal static class OneTimeInvitationClient
{
    private sealed record ClaimResponse(string? Id, string? Config);

    public static async Task<Invitation> RedeemAsync(OneTimeInvitation invite)
    {
        using var handler = new HttpClientHandler();
        handler.ServerCertificateCustomValidationCallback = (_, certificate, _, _) =>
            certificate is not null && CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(certificate.RawData), Convert.FromHexString(invite.CertificateSha256));
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
        using var request = new HttpRequestMessage(HttpMethod.Post, new UriBuilder("https", invite.Host, invite.Port, "claim").Uri)
        {
            Content = new StringContent(JsonSerializer.Serialize(new { token = invite.Token }), Encoding.UTF8, "application/json")
        };
        HttpResponseMessage response;
        try { response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead); }
        catch (HttpRequestException) { throw new IOException("Не удалось связаться с VPS для активации приглашения. Проверьте сеть и TCP-порт 8443."); }
        catch (TaskCanceledException) { throw new IOException("VPS не ответил на запрос активации. Проверьте TCP-порт 8443."); }
        using (response)
        {
            if (response.StatusCode == HttpStatusCode.Gone)
                throw new FormatException("Ссылка уже использована или доступ отозван. Попросите новую ссылку.");
            if (!response.IsSuccessStatusCode)
                throw new IOException("VPS не смог активировать приглашение. Попробуйте позже.");
            if (response.Content.Headers.ContentLength is > 60000)
                throw new FormatException("VPS вернул слишком большой ответ.");
            var json = await response.Content.ReadAsStringAsync();
            if (json.Length > 60000) throw new FormatException("VPS вернул слишком большой ответ.");
            ClaimResponse? claim;
            try { claim = JsonSerializer.Deserialize<ClaimResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }); }
            catch (JsonException) { throw new FormatException("VPS вернул повреждённые настройки."); }
            if (claim?.Id != invite.Id || claim.Config is null)
                throw new FormatException("VPS вернул настройки другого приглашения.");
            AmneziaWgConfig config;
            try { config = AmneziaWgConfig.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(claim.Config))); }
            catch { throw new FormatException("VPS вернул повреждённые настройки VPN."); }
            if (!config.FullTunnel || !config.Endpoint.StartsWith(invite.Host + ":", StringComparison.OrdinalIgnoreCase))
                throw new FormatException("VPS вернул настройки другого сервера.");
            return new Invitation(invite.Id, invite.Name, config);
        }
    }
}
