using System.Runtime.InteropServices;
using System.Security.Principal;
using System.ServiceProcess;

namespace HateVPN.Service;

internal static class Program
{
    [DllImport("kernel32.dll")] static extern bool SetDefaultDllDirectories(uint flags);
    public static readonly string ConfigPath = Path.Combine(AppContext.BaseDirectory,"State","HateVPN.conf.dpapi");
    public static readonly string AmneziaConfigPath = Path.Combine(AppContext.BaseDirectory,"State","HateVPNAWG.conf.dpapi");

    static int Main(string[] args)
    {
        SetDefaultDllDirectories(0x00000200 | 0x00000800);
        if (args.Length > 0 && args[0] == "--native-check")
        {
            foreach(var item in new[]{("tunnel.dll","WireGuardTunnelService"),("wireguard.dll","WireGuardOpenAdapter"),("amneziawg-tunnel.dll","WireGuardTunnelService")})
            { var handle=NativeLibrary.Load(Path.Combine(AppContext.BaseDirectory,item.Item1)); NativeLibrary.GetExport(handle,item.Item2); }
            return 0;
        }
        if (!WindowsIdentity.GetCurrent().IsSystem) return 5;
        if(args.Length >= 2 && args[0] == "/service")
        {
            if (!Path.GetFullPath(args[1]).Equals(ConfigPath,StringComparison.OrdinalIgnoreCase)) return 5;
            return Tunnel.Service.Run(ConfigPath) ? 0 : 1;
        }
        if(args.Length >= 2 && args[0] == "/awgservice")
        {
            if (!Path.GetFullPath(args[1]).Equals(AmneziaConfigPath,StringComparison.OrdinalIgnoreCase)) return 5;
            return Tunnel.Service.RunAmnezia(MachineSecret.Load(AmneziaConfigPath),"HateVPNAWG") ? 0 : 1;
        }
        ServiceBase.Run(new BrokerService());
        return 0;
    }
}
