using System.Globalization;
using System.IO.Pipes;
using System.Text;

namespace HateVPN.Service;

internal static class AmneziaStatus
{
    private const string PipeName = @"ProtectedPrefix\Administrators\AmneziaWG\HateVPNAWG";

    public static (DateTime? Handshake, ulong Received, ulong Sent) Read() =>
        ReadAsync().GetAwaiter().GetResult();

    private static async Task<(DateTime?, ulong, ulong)> ReadAsync()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        await pipe.ConnectAsync(timeout.Token);
        using var writer = new StreamWriter(pipe, new UTF8Encoding(false), leaveOpen: true) { NewLine = "\n", AutoFlush = true };
        using var reader = new StreamReader(pipe, Encoding.UTF8, leaveOpen: true);
        await writer.WriteAsync("get=1\n\n".AsMemory(), timeout.Token);
        long seconds = 0;
        ulong received = 0, sent = 0;
        var success = false;
        for (var i = 0; i < 128; i++)
        {
            var line = await reader.ReadLineAsync(timeout.Token);
            if (line is null || line.Length == 0) break;
            var split = line.IndexOf('=');
            if (split < 0) continue;
            var key = line[..split]; var value = line[(split + 1)..];
            switch (key)
            {
                case "last_handshake_time_sec": long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out seconds); break;
                case "rx_bytes": ulong.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out received); break;
                case "tx_bytes": ulong.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out sent); break;
                case "errno": success = value == "0"; break;
            }
        }
        if (!success) throw new IOException("AmneziaWG не вернул состояние туннеля.");
        DateTime? handshake = seconds > 0 ? DateTimeOffset.FromUnixTimeSeconds(seconds).UtcDateTime : null;
        return (handshake, received, sent);
    }
}
