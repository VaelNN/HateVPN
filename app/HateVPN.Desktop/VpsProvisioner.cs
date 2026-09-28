using HateVPN.Core;
using Renci.SshNet;
using Renci.SshNet.Common;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace HateVPN.Desktop;

internal sealed record VpsCredentials(string Host, int Port, string User, string Secret, bool IsPrivateKey);
internal enum VpsProtocol { AmneziaWg, XrayReality }
internal sealed record ProvisionedVps(string Config, string Endpoint, bool FullTunnel, string ProtocolName);

internal static class VpsProvisioner
{
    public static ProvisionedVps Install(VpsCredentials credentials, VpsProtocol protocol, Func<string, bool> trustHost, Action<string> progress)
    {
        var host = credentials.Host.Trim();
        if (host.Length is < 1 or > 253 || !Regex.IsMatch(host, @"^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$") ||
            host.Contains("..") || host.Contains("--") || IPAddress.TryParse(host, out var address) && address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
            throw new FormatException("Укажите IPv4-адрес или домен VPS без протокола.");
        if (credentials.Port is < 1 or > 65535) throw new FormatException("Порт SSH должен быть от 1 до 65535.");
        if (credentials.User != "root") throw new FormatException("Для автоматической установки нужен SSH-пользователь root.");
        if (string.IsNullOrWhiteSpace(credentials.Secret)) throw new FormatException("Введите пароль или закрытый SSH-ключ.");

        AuthenticationMethod auth;
        if (credentials.IsPrivateKey)
        {
            try
            {
                using var keyStream = new MemoryStream(Encoding.UTF8.GetBytes(credentials.Secret));
                auth = new PrivateKeyAuthenticationMethod(credentials.User, new PrivateKeyFile(keyStream));
            }
            catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or SshException)
            { throw new FormatException("Не удалось прочитать SSH-ключ. Вставьте полный закрытый ключ в формате OpenSSH или PEM."); }
        }
        else auth = new PasswordAuthenticationMethod(credentials.User, credentials.Secret);

        var connection = new ConnectionInfo(host, credentials.Port, credentials.User, auth)
        { Timeout = TimeSpan.FromSeconds(20) };
        string? acceptedFingerprint = null;
        var fingerprintRejected = false;
        bool CheckFingerprint(byte[] key)
        {
            var fingerprint = "SHA256:" + Convert.ToBase64String(SHA256.HashData(key)).TrimEnd('=');
            if (acceptedFingerprint is not null)
            {
                if (fingerprint == acceptedFingerprint) return true;
                fingerprintRejected = true;
                return false;
            }
            if (!trustHost(fingerprint)) { fingerprintRejected = true; return false; }
            acceptedFingerprint = fingerprint;
            return true;
        }
        using var ssh = new SshClient(connection);
        ssh.HostKeyReceived += (_, e) => e.CanTrust = CheckFingerprint(e.HostKey);

        progress("Подключаемся к VPS по SSH…");
        try { ssh.Connect(); }
        catch when (fingerprintRejected) { throw new FormatException("SSH-ключ сервера не подтверждён. Настройка отменена."); }
        if (!ssh.IsConnected) throw new IOException("SSH-соединение не установлено.");
        var useExistingAmnezia = false;
        if (protocol == VpsProtocol.AmneziaWg)
        {
            using var detect = ssh.CreateCommand("docker inspect -f '{{.State.Running}}' amnezia-awg2 2>/dev/null");
            detect.CommandTimeout = TimeSpan.FromSeconds(8);
            var containerState = detect.Execute().Trim();
            if (containerState.Equals("false", StringComparison.OrdinalIgnoreCase))
                throw new FormatException("VPN уже установлен на VPS, но его служба остановлена. Запустите сервер в AmneziaVPN.");
            useExistingAmnezia = containerState.Equals("true", StringComparison.OrdinalIgnoreCase);
            progress(useExistingAmnezia ? "Создаём отдельное подключение на сервере…" : "Проверяем систему и настраиваем сервер…");
        }
        else progress("Проверяем сервер и устанавливаем XRay REALITY…");
        using var sftp = new SftpClient(connection);
        sftp.HostKeyReceived += (_, e) => e.CanTrust = CheckFingerprint(e.HostKey);
        try { sftp.Connect(); }
        catch when (fingerprintRejected) { throw new IOException("SSH-ключ сервера изменился во время настройки. Подключение остановлено."); }
        var remotePath = "/tmp/hatevpn-setup-" + Guid.NewGuid().ToString("N") + ".sh";
        try
        {
            var resourceName = protocol == VpsProtocol.XrayReality ? "HateVPN.install-xray-server.sh"
                : useExistingAmnezia ? "HateVPN.add-amnezia-container-client.sh" : "HateVPN.install-amneziawg-server.sh";
            using var script = typeof(VpsProvisioner).Assembly.GetManifestResourceStream(resourceName)
                ?? throw new IOException("В установщике не найден сценарий настройки VPS.");
            sftp.UploadFile(script, remotePath);
            var arguments = protocol == VpsProtocol.AmneziaWg && useExistingAmnezia ? " 0 " + DeviceIdentity.GetOrCreate() : "";
            using var command = ssh.CreateCommand("bash " + remotePath + " " + host + arguments);
            command.CommandTimeout = TimeSpan.FromMinutes(15);
            var output = command.Execute();
            if (command.ExitStatus != 0)
            {
                var reason = command.Error.Trim();
                if (reason.Length > 350) reason = reason[^350..];
                throw new IOException(string.IsNullOrEmpty(reason) ? "Установка на VPS не завершилась." : reason);
            }
            progress("Проверяем конфигурацию…");
            if (protocol == VpsProtocol.XrayReality)
            {
                var line = output.Split('\n', StringSplitOptions.TrimEntries)
                    .FirstOrDefault(value => value.StartsWith("HATEVPN_LINK=", StringComparison.Ordinal));
                if (line is null) throw new IOException("Сервер настроен, но не вернул профиль XRay REALITY.");
                var node = XrayNode.Parse(line["HATEVPN_LINK=".Length..]);
                if (!node.Host.Equals(host, StringComparison.OrdinalIgnoreCase) || node.Port != 443)
                    throw new FormatException("Сервер вернул профиль с другим адресом.");
                return new ProvisionedVps(node.Link, node.Endpoint, true, "XRay REALITY");
            }
            var encoded = output.Split('\n', StringSplitOptions.TrimEntries)
                .FirstOrDefault(line => line.StartsWith("HATEVPN_AWG_CONFIG_BASE64=", StringComparison.Ordinal));
            if (encoded is null) throw new IOException("Сервер настроен, но не вернул профиль подключения.");
            try
            {
                var config = AmneziaWgConfig.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(
                    encoded["HATEVPN_AWG_CONFIG_BASE64=".Length..])));
                var endpointHost = config.Endpoint[..config.Endpoint.LastIndexOf(':')];
                if (!endpointHost.Equals(host, StringComparison.OrdinalIgnoreCase))
                    throw new FormatException("Сервер вернул профиль с другим адресом.");
                return new ProvisionedVps(config.Text, config.Endpoint, config.FullTunnel, "AmneziaWG");
            }
            catch (FormatException) { throw; }
            catch { throw new FormatException("Сервер вернул некорректный профиль подключения."); }
        }
        finally
        {
            try { sftp.DeleteFile(remotePath); } catch { /* Temporary script contains no credentials. */ }
            sftp.Disconnect();
            ssh.Disconnect();
        }
    }
}
