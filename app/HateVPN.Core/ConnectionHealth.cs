namespace HateVPN.Core;

public static class ConnectionHealth
{
    public static string Classify(DateTime? handshake, DateTime started, DateTime now)
    {
        if(handshake.HasValue && handshake.Value<=now.AddSeconds(5) && (now-handshake.Value).TotalSeconds<180) return "connected";
        return (now-started).TotalSeconds>25 ? "reconnecting" : "connecting";
    }

    public static string ClassifyTraffic(DateTime? handshake, DateTime started, DateTime now, ulong received, ulong sent)
    {
        var phase = Classify(handshake, started, now);
        if (phase == "connected" && (now - started).TotalSeconds > 10 && sent > 1048576 && received < 1024)
            return "no-data";
        return phase;
    }
}
