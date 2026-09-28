using System.Buffers.Binary;
using System.Text.Json;

namespace HateVPN.Core;

public record Request(string Command, string? Config = null, string? ProfileId = null);
public record Snapshot(string Phase, string? ProfileId = null, string? Endpoint = null, bool FullTunnel = false, ulong Received = 0, ulong Sent = 0, DateTime? Handshake = null, bool Owned = true, string Engine = "WireGuard");
public record Response(bool Success, string? Error = null, Snapshot? State = null);

public static class Protocol
{
    public const string PipeName = "HateVPN.Control.v1";
    public const string ServiceName = "HateVPNBroker";
    public static async Task WriteAsync<T>(Stream stream,T value,CancellationToken token)
    {
        var data=JsonSerializer.SerializeToUtf8Bytes(value);
        if(data.Length>65536) throw new InvalidDataException("Слишком большой запрос.");
        var header=new byte[4]; BinaryPrimitives.WriteInt32LittleEndian(header,data.Length);
        await stream.WriteAsync(header,token); await stream.WriteAsync(data,token); await stream.FlushAsync(token);
    }
    public static async Task<T> ReadAsync<T>(Stream stream,CancellationToken token)
    {
        var header=new byte[4]; await stream.ReadExactlyAsync(header,token);
        var length=BinaryPrimitives.ReadInt32LittleEndian(header);
        if(length<1||length>65536) throw new InvalidDataException("Некорректный размер запроса.");
        var data=new byte[length]; await stream.ReadExactlyAsync(data,token);
        return JsonSerializer.Deserialize<T>(data) ?? throw new InvalidDataException("Некорректный запрос.");
    }
}
