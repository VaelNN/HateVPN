using Microsoft.Win32;
using System.IO;
using System.Runtime.InteropServices;

namespace HateVPN.Desktop;

internal sealed class SystemProxyLease
{
    private const string InternetSettings = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
    private const string BackupKey = @"Software\HateVPN\ProxyBackup";
    private const string LocalProxy = "127.0.0.1:29452";
    [DllImport("wininet.dll",SetLastError=true)] private static extern bool InternetSetOption(IntPtr handle,int option,IntPtr buffer,int length);

    public void Acquire()
    {
        using var settings = Registry.CurrentUser.OpenSubKey(InternetSettings, writable:true)
            ?? throw new IOException("Не удалось открыть настройки прокси Windows.");
        using var backup = Registry.CurrentUser.CreateSubKey(BackupKey)
            ?? throw new IOException("Не удалось сохранить настройки прокси Windows.");
        if ((int?)backup.GetValue("Active") != 1)
        {
            backup.SetValue("Enabled", Convert.ToInt32(settings.GetValue("ProxyEnable", 0)), RegistryValueKind.DWord);
            backup.SetValue("Server", settings.GetValue("ProxyServer", "")?.ToString() ?? "", RegistryValueKind.String);
            backup.SetValue("Override", settings.GetValue("ProxyOverride", "")?.ToString() ?? "", RegistryValueKind.String);
            backup.SetValue("Active", 1, RegistryValueKind.DWord);
        }
        settings.SetValue("ProxyServer", LocalProxy, RegistryValueKind.String);
        settings.SetValue("ProxyEnable", 1, RegistryValueKind.DWord);
        Notify();
    }

    public void Release()
    {
        using var backup = Registry.CurrentUser.OpenSubKey(BackupKey, writable:true);
        if ((int?)backup?.GetValue("Active") != 1) return;
        using var settings = Registry.CurrentUser.OpenSubKey(InternetSettings, writable:true);
        if (settings is not null && settings.GetValue("ProxyServer")?.ToString() == LocalProxy)
        {
            settings.SetValue("ProxyEnable", Convert.ToInt32(backup.GetValue("Enabled", 0)), RegistryValueKind.DWord);
            var oldServer = backup.GetValue("Server")?.ToString() ?? "";
            if (oldServer.Length == 0) settings.DeleteValue("ProxyServer", false);
            else settings.SetValue("ProxyServer", oldServer, RegistryValueKind.String);
            var oldOverride = backup.GetValue("Override")?.ToString() ?? "";
            if (oldOverride.Length == 0) settings.DeleteValue("ProxyOverride", false);
            else settings.SetValue("ProxyOverride", oldOverride, RegistryValueKind.String);
            Notify();
        }
        backup.SetValue("Active", 0, RegistryValueKind.DWord);
    }

    private static void Notify()
    {
        InternetSetOption(IntPtr.Zero,39,IntPtr.Zero,0);
        InternetSetOption(IntPtr.Zero,37,IntPtr.Zero,0);
    }
}
