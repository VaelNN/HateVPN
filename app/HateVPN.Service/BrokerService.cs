using HateVPN.Core;
using System.ComponentModel;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;

namespace HateVPN.Service;

internal sealed class BrokerService : ServiceBase
{
    private readonly CancellationTokenSource _stop=new();
    private readonly object _gate=new();
    private Task _server;
    private string _owner, _profileId;
    private WireGuardConfig _config;
    private AmneziaWgConfig _amneziaConfig;
    private EndpointRoute _endpointRoute;
    private XrayRuntime _xray;
    private XrayNode _xrayNode;
    private DateTime _started;

    public BrokerService() { ServiceName=Protocol.ServiceName; CanStop=true; CanShutdown=true; AutoLog=true; }
    protected override void OnStart(string[] args)
    {
        _server=Task.Run(Serve);
    }
    protected override void OnStop()
    {
        RequestAdditionalTime(30000);
        StopBroker();
    }
    private void StopBroker()
    {
        _stop.Cancel();
        try { _server?.Wait(5000); } catch { }
        lock(_gate) StopTunnel();
    }
    protected override void OnShutdown() => StopBroker();

    private async Task Serve()
    {
        try { lock(_gate) StopTunnel(); } catch { }
        while(!_stop.IsCancellationRequested)
        {
            try
            {
                using var pipe=LocalControlPipe.Create();
                await pipe.WaitForConnectionAsync(_stop.Token);
                using var deadline=CancellationTokenSource.CreateLinkedTokenSource(_stop.Token); deadline.CancelAfter(TimeSpan.FromSeconds(10));
                var request=await Protocol.ReadAsync<Request>(pipe,deadline.Token);
                string sid=LocalControlPipe.ClientSid(pipe);
                Response response;
                lock(_gate)
                {
                    if(_stop.IsCancellationRequested) break;
                    try { response=Handle(request,sid); }
                    catch(FormatException ex) { response=new(false,ex.Message); }
                    catch(Win32Exception ex) { response=new(false,$"Не удалось управлять VPN. Код Windows: {ex.NativeErrorCode}."); }
                    catch { response=new(false,"Ошибка службы VPN. Повторите попытку или перезапустите службу HateVPNBroker."); }
                }
                using var send=CancellationTokenSource.CreateLinkedTokenSource(_stop.Token); send.CancelAfter(3000);
                await Protocol.WriteAsync(pipe,response,send.Token);
            }
            catch(OperationCanceledException) when(_stop.IsCancellationRequested) { break; }
            catch { if(!_stop.IsCancellationRequested) await Task.Delay(150); }
        }
    }

    private Response Handle(Request request,string sid)
    {
        if(string.IsNullOrWhiteSpace(sid)) return new(false,"Не удалось подтвердить пользователя Windows.");
        if(request.Command=="status") return new(true,State:GetSnapshot(sid));
        if(_owner!=null && _owner!=sid) return new(false,"VPN используется другим пользователем Windows.");
        if(request.Command=="disconnect") { StopTunnel(); return new(true,State:new("off")); }
        if(request.Command!="connect") return new(false,"Неизвестная команда.");
        if(!Guid.TryParse(request.ProfileId,out _)) return new(false,"Некорректный профиль.");
        if(_owner!=null) return new(false,"Сначала отключите текущий сервер.");
        if (request.Config?.StartsWith("vless://",StringComparison.OrdinalIgnoreCase) == true)
        {
            var node=XrayNode.Parse(request.Config);
            try
            {
                _xray=new XrayRuntime(node.Build());
                _xrayNode=node; _owner=sid; _profileId=request.ProfileId; _started=DateTime.UtcNow;
                return new(true,State:GetSnapshot(sid));
            }
            catch { StopTunnel(); throw; }
        }
        if (AmneziaWgConfig.IsAmnezia(request.Config ?? ""))
        {
            var awg=AmneziaWgConfig.Parse(request.Config ?? "");
            try
            {
                _endpointRoute=EndpointRoute.Pin(awg.Endpoint);
                MachineSecret.Save(Program.AmneziaConfigPath,awg.Text);
                Tunnel.Service.Add(Program.AmneziaConfigPath,false,true);
                TunnelDns.Apply(awg);
                _owner=sid; _profileId=request.ProfileId; _amneziaConfig=awg; _started=DateTime.UtcNow;
                // The first network request drives the handshake; do not delay the connect reply
                // while the tunnel's status pipe is still becoming available.
                return new(true,State:new("connecting",_profileId,awg.Endpoint,awg.FullTunnel,Engine:"AmneziaWG"));
            }
            catch { StopTunnel(); throw; }
        }
        var config=WireGuardConfig.Parse(request.Config ?? "");
        MachineSecret.Save(Program.ConfigPath,config.Text);
        try
        {
            Tunnel.Service.Add(Program.ConfigPath,false);
            _owner=sid; _profileId=request.ProfileId; _config=config; _started=DateTime.UtcNow;
            return new(true,State:GetSnapshot(sid));
        }
        catch { StopTunnel(); throw; }
    }

    private Snapshot GetSnapshot(string sid)
    {
        if(_owner==null) return new("off");
        if(sid!=_owner) return new("other",Owned:false);
        if (_xray is not null)
        {
            var phase = !_xray.IsRunning ? "error" : _xray.Healthy ? "connected" : _xray.ProxyHealthy ? "partial" :
                (DateTime.UtcNow-_started).TotalSeconds < 30 ? "connecting" : "reconnecting";
            return new(phase,_profileId,_xrayNode?.Endpoint,true,Engine:"Xray");
        }
        if (_amneziaConfig is not null)
        {
            try
            {
                var (handshake, received, sent) = AmneziaStatus.Read();
                return new(ConnectionHealth.ClassifyTraffic(handshake,_started,DateTime.UtcNow,received,sent),_profileId,
                    _amneziaConfig.Endpoint,_amneziaConfig.FullTunnel,received,sent,handshake,Engine:"AmneziaWG");
            }
            catch
            {
                bool running;
                try { using var controller=new ServiceController("HateVPNAWG"); running=controller.Status is ServiceControllerStatus.Running or ServiceControllerStatus.StartPending; }
                catch { running=false; }
                return new(running && (DateTime.UtcNow-_started).TotalSeconds<25 ? "connecting" : "error",
                    _profileId,_amneziaConfig.Endpoint,_amneziaConfig.FullTunnel,Engine:"AmneziaWG");
            }
        }
        try
        {
            using var adapter=new Tunnel.Driver.Adapter("HateVPN");
            var config=adapter.GetConfiguration();
            var peer=config.Peers.Single();
            var last=peer.LastHandshake==default ? (DateTime?)null : peer.LastHandshake;
            var phase=ConnectionHealth.Classify(last,_started,DateTime.UtcNow);
            return new(phase,_profileId,_config.Endpoint,_config.FullTunnel,peer.RxBytes,peer.TxBytes,last);
        }
        catch
        {
            bool running;
            try { using var controller=new ServiceController("WireGuardTunnel$HateVPN"); running=controller.Status is ServiceControllerStatus.Running or ServiceControllerStatus.StartPending; }
            catch { running=false; }
            return new(running && (DateTime.UtcNow-_started).TotalSeconds<25 ? "connecting" : "error",_profileId,_config.Endpoint,_config.FullTunnel);
        }
    }

    private void StopTunnel()
    {
        try
        {
            _xray?.Dispose(); _xray=null; _xrayNode=null;
            Tunnel.Service.Remove(Program.AmneziaConfigPath,true,true);
            Tunnel.Service.Remove(Program.ConfigPath,true);
            if(File.Exists(Program.AmneziaConfigPath)) File.Delete(Program.AmneziaConfigPath);
            if(File.Exists(Program.ConfigPath)) File.Delete(Program.ConfigPath);
        }
        finally
        {
            _endpointRoute?.Dispose(); _endpointRoute=null;
            _owner=null; _profileId=null; _config=null; _amneziaConfig=null;
        }
    }
}
