using System.Security.AccessControl;
using System.Security.Principal;

namespace HateVPN.Core;

public static class DeviceIdentity
{
    public static string GetOrCreate()
    {
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HateVPN");
        Directory.CreateDirectory(directory);
        var security = new DirectorySecurity();
        security.SetAccessRuleProtection(true, false);
        foreach (var sid in new[] { WindowsIdentity.GetCurrent().User!, new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null) })
            security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(directory).SetAccessControl(security);
        var path = Path.Combine(directory, "device-id.txt");
        if (!File.Exists(path))
        {
            using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            using var writer = new StreamWriter(file);
            writer.Write("hv-" + Guid.NewGuid().ToString("N"));
        }
        var id = File.ReadAllText(path).Trim();
        if (!System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9=-]{10,64}$"))
            throw new InvalidDataException("Идентификатор устройства повреждён.");
        return id;
    }
}
