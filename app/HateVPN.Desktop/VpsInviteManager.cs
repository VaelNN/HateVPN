using HateVPN.Core;
using Renci.SshNet;
using Renci.SshNet.Common;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace HateVPN.Desktop;

internal sealed record ServerInvite(string Id, string Name);

internal static class VpsInviteManager
{
    public static string Create(VpsCredentials credentials, string name, Func<string, bool> trustHost, Action<string> progress)
    {
        var id = "hv-" + Guid.NewGuid().ToString("N");
        var safeName = new string(name.Trim().Where(c => !char.IsControl(c)).Take(48).ToArray());
        if (safeName.Length == 0) throw new FormatException("Введите имя друга.");
        if (Encoding.UTF8.GetByteCount(safeName) > 96) throw new FormatException("Имя друга слишком длинное.");
        string? acceptedFingerprint = null;
        bool TrustOnce(string fingerprint)
        {
            if (acceptedFingerprint is not null) return acceptedFingerprint == fingerprint;
            if (!trustHost(fingerprint)) return false;
            acceptedFingerprint = fingerprint;
            return true;
        }
        var label = Convert.ToBase64String(Encoding.UTF8.GetBytes(safeName));
        var output = Run(credentials, "HateVPN.add-amnezia-container-client.sh",
            credentials.Host.Trim() + " 0 " + id + " " + label, TrustOnce, progress);
        var encoded = output.Split('\n', StringSplitOptions.TrimEntries)
            .FirstOrDefault(line => line.StartsWith("HATEVPN_AWG_CONFIG_BASE64=", StringComparison.Ordinal));
        if (encoded is null) throw new IOException("Сервер создал приглашение, но не вернул настройки.");
        var config = AmneziaWgConfig.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(encoded["HATEVPN_AWG_CONFIG_BASE64=".Length..])));
        if (!config.Endpoint.StartsWith(credentials.Host.Trim() + ":", StringComparison.OrdinalIgnoreCase))
            throw new FormatException("Сервер вернул профиль с другим адресом.");
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        try
        {
            progress("Готовим одноразовую ссылку…");
            var activation = Run(credentials, "HateVPN.install-one-time-invites.sh",
                credentials.Host.Trim() + " " + id + " " + token, TrustOnce, progress);
            var fingerprint = activation.Split('\n', StringSplitOptions.TrimEntries)
                .FirstOrDefault(line => line.StartsWith("HATEVPN_CLAIM_CERT_SHA256=", StringComparison.Ordinal))?
                ["HATEVPN_CLAIM_CERT_SHA256=".Length..];
            if (fingerprint is null) throw new IOException("VPS не подтвердил готовность одноразовых ссылок.");
            return OneTimeInvitationLink.Create(id, safeName, credentials.Host.Trim(), 8443, fingerprint, token);
        }
        catch
        {
            try { Revoke(credentials, id, TrustOnce, _ => { }); } catch { }
            throw;
        }
    }

    public static IReadOnlyList<ServerInvite> List(VpsCredentials credentials, Func<string, bool> trustHost, Action<string> progress)
    {
        var output = Run(credentials, "HateVPN.manage-amnezia-container-invites.sh", "list", trustHost, progress);
        var result = new List<ServerInvite>();
        foreach (var line in output.Split('\n', StringSplitOptions.TrimEntries))
        {
            if (!line.StartsWith("HATEVPN_INVITE=", StringComparison.Ordinal)) continue;
            var pair = line["HATEVPN_INVITE=".Length..].Split(':', 2);
            if (pair.Length != 2 || !Regex.IsMatch(pair[0], "^hv-[0-9a-f]{32}$")) continue;
            try
            {
                var name = Encoding.UTF8.GetString(Convert.FromBase64String(pair[1]));
                if (name.Length is > 0 and <= 48 && !name.Any(char.IsControl)) result.Add(new(pair[0], name));
            }
            catch (FormatException) { }
        }
        return result;
    }

    public static void Revoke(VpsCredentials credentials, string id, Func<string, bool> trustHost, Action<string> progress)
    {
        if (!Regex.IsMatch(id, "^hv-[0-9a-f]{32}$")) throw new FormatException("Некорректное приглашение.");
        var output = Run(credentials, "HateVPN.manage-amnezia-container-invites.sh", "revoke " + id, trustHost, progress);
        if (!output.Split('\n', StringSplitOptions.TrimEntries).Contains("HATEVPN_REVOKED=" + id))
            throw new IOException("Сервер не подтвердил отзыв доступа.");
    }

    private static string Run(VpsCredentials credentials, string resourceName, string arguments,
        Func<string, bool> trustHost, Action<string> progress)
    {
        var host = credentials.Host.Trim();
        if (host.Length is < 1 or > 253 || !Regex.IsMatch(host, @"^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$") ||
            host.Contains("..") || host.Contains("--") || IPAddress.TryParse(host, out var address) && address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
            throw new FormatException("Укажите IPv4-адрес или домен VPS без протокола.");
        if (credentials.Port is < 1 or > 65535 || credentials.User != "root" || string.IsNullOrWhiteSpace(credentials.Secret))
            throw new FormatException("Для управления приглашениями введите адрес, SSH-порт и доступ root.");
        AuthenticationMethod auth;
        if (credentials.IsPrivateKey)
        {
            try
            {
                using var stream = new MemoryStream(Encoding.UTF8.GetBytes(credentials.Secret));
                auth = new PrivateKeyAuthenticationMethod(credentials.User, new PrivateKeyFile(stream));
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or SshException)
            { throw new FormatException("Не удалось прочитать закрытый SSH-ключ."); }
        }
        else auth = new PasswordAuthenticationMethod(credentials.User, credentials.Secret);
        var connection = new ConnectionInfo(host, credentials.Port, credentials.User, auth) { Timeout = TimeSpan.FromSeconds(20) };
        string? acceptedFingerprint = null;
        var rejected = false;
        bool Check(byte[] key)
        {
            var fingerprint = "SHA256:" + Convert.ToBase64String(SHA256.HashData(key)).TrimEnd('=');
            if (acceptedFingerprint is not null)
            {
                if (acceptedFingerprint == fingerprint) return true;
                rejected = true;
                return false;
            }
            if (!trustHost(fingerprint)) { rejected = true; return false; }
            acceptedFingerprint = fingerprint;
            return true;
        }
        using var ssh = new SshClient(connection);
        ssh.HostKeyReceived += (_, e) => e.CanTrust = Check(e.HostKey);
        progress("Подключаемся к VPS…");
        try { ssh.Connect(); }
        catch when (rejected) { throw new FormatException("SSH-ключ сервера не подтверждён."); }
        if (!ssh.IsConnected) throw new IOException("SSH-соединение не установлено.");
        using var sftp = new SftpClient(connection);
        sftp.HostKeyReceived += (_, e) => e.CanTrust = Check(e.HostKey);
        try { sftp.Connect(); }
        catch when (rejected) { throw new FormatException("SSH-ключ сервера изменился."); }
        var remotePath = "/tmp/hatevpn-invite-" + Guid.NewGuid().ToString("N") + ".sh";
        try
        {
            using var script = typeof(VpsInviteManager).Assembly.GetManifestResourceStream(resourceName)
                ?? throw new IOException("В приложении нет сценария управления приглашениями.");
            sftp.UploadFile(script, remotePath);
            progress("Обновляем доступ на сервере…");
            using var command = ssh.CreateCommand("bash " + remotePath + " " + arguments);
            command.CommandTimeout = TimeSpan.FromMinutes(2);
            var output = command.Execute();
            if (command.ExitStatus != 0)
            {
                var reason = command.Error.Trim();
                if (reason.Length > 350) reason = reason[^350..];
                throw new IOException(string.IsNullOrEmpty(reason) ? "Операция на сервере не завершилась." : reason);
            }
            return output;
        }
        finally
        {
            try { sftp.DeleteFile(remotePath); } catch { }
            sftp.Disconnect();
            ssh.Disconnect();
        }
    }
}
