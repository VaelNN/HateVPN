using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace HateVPN.Desktop;

internal sealed record ConnectivityResult(bool Success, string Detail, DateTime CheckedAt);

internal static class ConnectivityProbe
{
    private enum Attempt { Unavailable, WrongRoute, ThroughTunnel }

    private static readonly Uri[] Targets =
    [
        new("https://www.example.com/"),
        new("https://www.microsoft.com/")
    ];

    public static async Task<ConnectivityResult> CheckAsync(string config, CancellationToken cancellationToken = default)
    {
        var address = Regex.Match(config, @"(?im)^\s*Address\s*=\s*([0-9.]+)(?:/\d+)").Groups[1].Value;
        if (!IPAddress.TryParse(address, out var tunnelIp) || tunnelIp.AddressFamily != AddressFamily.InterNetwork)
            return new(false, "Не удалось определить адрес VPN-адаптера.", DateTime.UtcNow);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var pending = Targets.Select(target => CheckTargetAsync(target, tunnelIp, timeout.Token)).ToList();
        var hasWrongRoute = false;
        while (pending.Count > 0)
        {
            var finished = await Task.WhenAny(pending);
            pending.Remove(finished);
            var attempt = await finished;
            if (attempt == Attempt.ThroughTunnel)
            {
                timeout.Cancel();
                return new(true, "Сайт открылся через VPN-адаптер.", DateTime.UtcNow);
            }
            hasWrongRoute |= attempt == Attempt.WrongRoute;
        }
        cancellationToken.ThrowIfCancellationRequested();
        var detail = hasWrongRoute ? "Сайт открылся вне VPN-адаптера. Проверьте маршруты." :
            "Сайты не открылись через VPN. Проверьте DNS и соединение с сервером.";
        return new(false, detail, DateTime.UtcNow);
    }

    private static async Task<Attempt> CheckTargetAsync(Uri target, IPAddress tunnelIp, CancellationToken token)
    {
        IPAddress? sourceIp = null;
        using var handler = new SocketsHttpHandler
        {
            UseProxy = false,
            AllowAutoRedirect = true,
            ConnectCallback = async (context, connectToken) =>
            {
                var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, connectToken);
                Exception? lastError = null;
                foreach (var remote in addresses.Where(ip => ip.AddressFamily == AddressFamily.InterNetwork))
                {
                    var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                    try
                    {
                        await socket.ConnectAsync(new IPEndPoint(remote, context.DnsEndPoint.Port), connectToken);
                        sourceIp = ((IPEndPoint)socket.LocalEndPoint!).Address;
                        return new NetworkStream(socket, ownsSocket: true);
                    }
                    catch (Exception ex) when (ex is SocketException or OperationCanceledException)
                    {
                        socket.Dispose(); lastError = ex;
                        if (ex is OperationCanceledException) throw;
                    }
                }
                throw new HttpRequestException("Нет доступного IPv4-адреса сайта.", lastError);
            }
        };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(7) };
        try
        {
            using var response = await client.GetAsync(target, HttpCompletionOption.ResponseHeadersRead, token);
            if ((int)response.StatusCode is >= 200 and < 400)
                return sourceIp?.Equals(tunnelIp) == true ? Attempt.ThroughTunnel : Attempt.WrongRoute;
        }
        catch (HttpRequestException) { }
        catch (SocketException) { }
        catch (IOException) { }
        catch (OperationCanceledException) { }
        return Attempt.Unavailable;
    }
}
