using HateVPN.Core;
using Microsoft.Win32.SafeHandles;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;

namespace HateVPN.Desktop;

internal sealed class BrokerClient
{
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe,out uint pid);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenSCManager(string? machine,string? database,uint access);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenService(IntPtr manager,string name,uint access);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool QueryServiceStatusEx(IntPtr service,int level,out ServiceStatusProcess status,int size,out int required);
    [DllImport("advapi32.dll")] static extern bool CloseServiceHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] private struct ServiceStatusProcess
    { public uint Type,State,Controls,ExitCode,SpecificExitCode,Checkpoint,WaitHint,ProcessId,Flags; }

    public async Task<Response> SendAsync(Request request)
    {
        using var deadline=new CancellationTokenSource(TimeSpan.FromSeconds(request.Command=="status" ? 3 : 35));
        using var pipe=new NamedPipeClientStream(".",Protocol.PipeName,PipeDirection.InOut,PipeOptions.Asynchronous,System.Security.Principal.TokenImpersonationLevel.Identification);
        await pipe.ConnectAsync(1200,deadline.Token);
        VerifyServer(pipe);
        await Protocol.WriteAsync(pipe,request,deadline.Token);
        return await Protocol.ReadAsync<Response>(pipe,deadline.Token);
    }

    private static void VerifyServer(NamedPipeClientStream pipe)
    {
        if(!GetNamedPipeServerProcessId(pipe.SafePipeHandle,out var pid)) throw new IOException("Не удалось проверить службу.");
        if(pid!=BrokerProcessId()) throw new IOException("Канал подключения не принадлежит системной службе HateVPN.");
    }

    private static uint BrokerProcessId()
    {
        var manager=OpenSCManager(null,null,1);
        if(manager==IntPtr.Zero) throw new IOException("Не удалось проверить диспетчер служб Windows.");
        try
        {
            var service=OpenService(manager,Protocol.ServiceName,4);
            if(service==IntPtr.Zero) throw new IOException("Служба HateVPN не установлена.");
            try
            {
                if(!QueryServiceStatusEx(service,0,out var state,Marshal.SizeOf<ServiceStatusProcess>(),out _) || state.State!=4 || state.ProcessId==0)
                    throw new IOException("Служба HateVPN не запущена.");
                return state.ProcessId;
            }
            finally { CloseServiceHandle(service); }
        }
        finally { CloseServiceHandle(manager); }
    }
}
