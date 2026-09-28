using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

namespace HateVPN.Service;

internal static class MachineSecret
{
    [StructLayout(LayoutKind.Sequential)] struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CryptProtectData(ref Blob input,string description,IntPtr entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
    [DllImport("crypt32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CryptUnprotectData(ref Blob input,out IntPtr description,IntPtr entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr ptr);
    public static void Save(string path,string config)
    {
        var directory=Path.GetDirectoryName(path)!;
        if(Directory.Exists(directory) && (File.GetAttributes(directory)&FileAttributes.ReparsePoint)!=0) throw new IOException("Недопустимый каталог службы.");
        Directory.CreateDirectory(directory);
        var acl=new DirectorySecurity(); acl.SetAccessRuleProtection(true,false);
        foreach(var kind in new[]{WellKnownSidType.LocalSystemSid,WellKnownSidType.BuiltinAdministratorsSid})
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(kind,null),FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
        new DirectoryInfo(directory).SetAccessControl(acl);
        if(File.Exists(path) && (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("Недопустимый файл службы.");
        var bytes=Encoding.UTF8.GetBytes(config);
        var input=new Blob{Length=bytes.Length,Data=Marshal.AllocHGlobal(bytes.Length)};
        Marshal.Copy(bytes,0,input.Data,bytes.Length);
        try
        {
            // WireGuard authenticates the DPAPI description against the tunnel filename.
            if(!CryptProtectData(ref input,"HateVPN",IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,5,out var output)) throw new Win32Exception();
            try { var encrypted=new byte[output.Length]; Marshal.Copy(output.Data,encrypted,0,encrypted.Length); File.WriteAllBytes(path,encrypted); }
            finally { LocalFree(output.Data); }
        }
        finally { Array.Clear(bytes); Marshal.Copy(bytes,0,input.Data,bytes.Length); Marshal.FreeHGlobal(input.Data); }
    }
    public static string Load(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("Недопустимый файл службы.");
        var encrypted=File.ReadAllBytes(path);
        var input=new Blob { Length=encrypted.Length,Data=Marshal.AllocHGlobal(encrypted.Length) };
        Marshal.Copy(encrypted,0,input.Data,encrypted.Length);
        try
        {
            if (!CryptUnprotectData(ref input,out var description,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,1,out var output))
                throw new Win32Exception();
            try
            {
                if (Marshal.PtrToStringUni(description) != "HateVPN") throw new IOException("Недопустимая конфигурация службы.");
                var bytes=new byte[output.Length];
                try { Marshal.Copy(output.Data,bytes,0,bytes.Length); return Encoding.UTF8.GetString(bytes); }
                finally { Array.Clear(bytes); }
            }
            finally { LocalFree(description); LocalFree(output.Data); }
        }
        finally { Array.Clear(encrypted); Marshal.FreeHGlobal(input.Data); }
    }
}
