using System.Security.AccessControl;
using System.Security.Principal;
using System.Security.Cryptography;
using System.Text.Json;

namespace HateVPN.Core;

public record Profile(string Id, string Name, string Config, string Endpoint, bool FullTunnel, string? SubscriptionUrl = null, bool IsInvitation = false, string? InvitationId = null)
{
    public override string ToString() => Name;
}
public class ProfileData
{
    public List<Profile> Profiles { get; set; } = [];
    public string? SelectedId { get; set; }
}
public sealed class ProfileStore
{
    private readonly string _directory;
    private string FilePath => Path.Combine(_directory,"profiles.v1.bin");
    public ProfileStore(string? directory=null) => _directory=directory ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"HateVPN");
    public ProfileData Load()
    {
        if(!File.Exists(FilePath)) return new();
        var ciphertext=File.ReadAllBytes(FilePath);
        var plaintext=ProtectedData.Unprotect(ciphertext,null,DataProtectionScope.CurrentUser);
        try { return JsonSerializer.Deserialize<ProfileData>(plaintext) ?? throw new InvalidDataException("Хранилище профилей повреждено."); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }
    public void Save(ProfileData data)
    {
        Directory.CreateDirectory(_directory);
        var security=new DirectorySecurity(); security.SetAccessRuleProtection(true,false);
        foreach(var sid in new[]{WindowsIdentity.GetCurrent().User!,new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null)})
            security.AddAccessRule(new FileSystemAccessRule(sid,FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
        new DirectoryInfo(_directory).SetAccessControl(security);
        var plaintext=JsonSerializer.SerializeToUtf8Bytes(data);
        try
        {
            var encrypted=ProtectedData.Protect(plaintext,null,DataProtectionScope.CurrentUser);
            var temp=Path.Combine(_directory,"profiles."+Guid.NewGuid().ToString("N")+".tmp");
            try { File.WriteAllBytes(temp,encrypted); File.Move(temp,FilePath,true); }
            finally { if(File.Exists(temp)) File.Delete(temp); }
        }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }
}
