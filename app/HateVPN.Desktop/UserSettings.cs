using Microsoft.Win32;
using System.IO;
using System.Text.Json;

namespace HateVPN.Desktop;

internal sealed class UserSettings
{
    public bool CloseToTray { get; set; } = true;
    private static string PathName => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"HateVPN","settings.json");
    public static UserSettings Load()
    {
        try { return JsonSerializer.Deserialize<UserSettings>(File.ReadAllText(PathName)) ?? new(); }
        catch { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PathName)!);
        var temp=PathName+".tmp"; File.WriteAllText(temp,JsonSerializer.Serialize(this)); File.Move(temp,PathName,true);
    }
    public static bool AutostartEnabled
    {
        get { using var key=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"); return key?.GetValue("HateVPN") is string; }
        set
        {
            using var key=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            if(value) key.SetValue("HateVPN",$"\"{Environment.ProcessPath}\" --background"); else key.DeleteValue("HateVPN",false);
        }
    }
}
