using HateVPN.Core;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

int count=0;
void Check(bool condition,string label) { if(!condition) throw new Exception("FAILED: "+label); count++; Console.WriteLine("PASS "+label); }
void Reject(string text,string label) { try { WireGuardConfig.Parse(text); } catch(FormatException) { Check(true,label); return; } throw new Exception("Accepted invalid config: "+label); }
var key=Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
var pub=Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
var input=$"[Interface]\nPrivateKey = {key}\nAddress = 10.77.0.2/32\nDNS = 1.1.1.1\n[Peer]\nPublicKey = {pub}\nEndpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0\n";
var parsed=WireGuardConfig.Parse(input);
Check(parsed.FullTunnel && parsed.Text.Contains("::/0"),"full tunnel includes IPv6 to prevent bypass");
Check(parsed.Text.Contains("PersistentKeepalive = 25"),"keepalive default supports monitoring and NAT");
Check(WireGuardConfig.Parse(parsed.Text).Text==parsed.Text,"normalization is stable");
Reject(input.Replace("DNS = 1.1.1.1","PostUp = powershell.exe\nDNS = 1.1.1.1"),"reject script hooks");
Reject(input+"[Peer]\nPublicKey = "+pub,"reject multiple peers");
Reject(input.Replace(key,"invalid"),"reject invalid keys");
Reject(input.Replace("10.77.0.2/32","10.77.0.2/99"),"reject invalid CIDR");
Reject(input.Replace("vpn.example.com:51820","example.com"),"reject endpoint without port");
Reject(input.Replace("vpn.example.com:51820","user@example.com:51820"),"reject endpoint credentials");
Reject(input.Replace("DNS = 1.1.1.1\n",""),"require explicit DNS");
Reject(input.Replace("DNS = 1.1.1.1","DNS = 1.1.1.1\nDNS = 8.8.8.8"),"reject duplicate directives");
Reject(input+"Jc = 3","reject AmneziaWG extensions");
var awgText=input.Replace("DNS = 1.1.1.1", "DNS = 1.1.1.1\nJc = 5\nJmin = 40\nJmax = 70\nS1 = 20\nS2 = 40\nH1 = 111111\nH2 = 222222\nH3 = 333333\nH4 = 444444");
var awg=AmneziaWgConfig.Parse(awgText);
Check(AmneziaWgConfig.IsAmnezia(awg.Text) && awg.FullTunnel && awg.Text.Contains("::/0"),"AmneziaWG profile retains obfuscation and full tunnel");
Check(AmneziaWgConfig.Parse(awg.Text).Text==awg.Text,"AmneziaWG normalization is stable");
var inviteId="hv-"+Guid.NewGuid().ToString("N");
var invitation=InvitationLink.Parse(InvitationLink.Create(inviteId,"Друг",awg.Text));
Check(invitation.Id==inviteId && invitation.Name=="Друг" && invitation.Config.Text==awg.Text,"friend invitation keeps its own VPN configuration");
Check(ConnectionLink.Detect("  https://sub.example.com/private-token  ")==ConnectionLinkKind.Subscription,"one link field accepts an HTTPS subscription");
Check(ConnectionLink.Detect("  "+InvitationLink.Create(inviteId,"Друг",awg.Text)+"  ")==ConnectionLinkKind.Invitation,"one link field accepts a friend invitation");
var claimToken=Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
var claimFingerprint=Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
var claimLink=OneTimeInvitationLink.Create(inviteId,"Друг","vpn.example.com",8443,claimFingerprint,claimToken);
var claim=OneTimeInvitationLink.Parse(claimLink);
Check(claim.Id==inviteId && claim.Token==claimToken && claim.CertificateSha256==claimFingerprint && !claimLink.Contains("PrivateKey"),"one-time link contains claim token instead of VPN configuration");
Check(ConnectionLink.Detect(claimLink)==ConnectionLinkKind.OneTimeInvitation,"one link field accepts a one-time invitation");
bool damagedClaimRejected=false; try { OneTimeInvitationLink.Parse(claimLink[..^1]+"$"); } catch(FormatException) { damagedClaimRejected=true; }
Check(damagedClaimRejected,"damaged one-time invitation is rejected");
bool unsafeLinkRejected=false; try { ConnectionLink.Detect("http://example.com/subscription"); } catch(FormatException) { unsafeLinkRejected=true; }
Check(unsafeLinkRejected,"one link field rejects an insecure or unknown link");
var invitedProfile=new Profile(Guid.NewGuid().ToString("D"),"Доступ · Друг",invitation.Config.Text,invitation.Config.Endpoint,true,IsInvitation:true,InvitationId:inviteId);
var invitedEntry=ConnectionCatalog.Entries(new ProfileData { Profiles=[invitedProfile],SelectedId=invitedProfile.Id }).Single();
Check(!invitedEntry.Description.Contains("vpn.example.com") && invitedEntry.IsSelected && Guid.TryParse(invitedProfile.Id,out _) && invitedProfile.InvitationId==inviteId,"friend's profile uses a valid client ID and hides server address");
bool malformedInviteRejected=false;
try { InvitationLink.Parse("hatevpn://invite/invalid"); } catch(FormatException) { malformedInviteRejected=true; }
Check(malformedInviteRejected,"damaged invitation is rejected");
var legacyProfile=JsonSerializer.Deserialize<Profile>("{\"Id\":\"old\",\"Name\":\"Old\",\"Config\":\"\",\"Endpoint\":\"example.com:443\",\"FullTunnel\":true,\"SubscriptionUrl\":null}");
Check(legacyProfile is { IsInvitation:false },"existing saved profiles remain compatible");
bool awgRejected=false; try { AmneziaWgConfig.Parse(awgText.Replace("H4 = 444444","H4 = 111111")); } catch(FormatException) { awgRejected=true; }
Check(awgRejected,"AmneziaWG rejects duplicate packet headers");
var awg3Text=awgText.Replace("S2 = 40","S2 = 40\nS3 = 33\nS4 = 12\nHeaderProtectionKey = "+Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))+"\nContentPaddingAddition = 10-100\nRandomTrailers = on\nDisableCookies = on\nI1 = <b 0x12345678>").Replace("AllowedIPs = 0.0.0.0/0","AllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 22-30");
var awg3=AmneziaWgConfig.Parse(awg3Text);
Check(awg3.Text.Contains("HeaderProtectionKey = ") && awg3.Text.Contains("PersistentKeepalive = 22-30") && awg3.Text.Contains("I1 = <b 0x12345678>"),"AmneziaWG 3.1 export parameters are preserved");
Check(AmneziaWgConfig.Parse(awg3.Text).Text==awg3.Text,"AmneziaWG 3.1 import is stable");
var smallHeaders=awg3Text.Replace("H1 = 111111","H1 = 1").Replace("H2 = 222222","H2 = 2").Replace("H3 = 333333","H3 = 3").Replace("H4 = 444444","H4 = 4").Replace("Jmin = 40","Jmin = 10").Replace("Jmax = 70","Jmax = 50").Replace("S2 = 40","S2 = 12").Replace("I1 = <b 0x12345678>","I1 = <r 2><b 0x858000010001000000000669636c6f756403636f6d0000010001c00c000100010000105a00044d583737>").Replace("ContentPaddingAddition = 10-100","RekeyAfterTime = 100-120\nRekeyTimeout = 3-7\nRejectAfterTime = 150-180\nKeepaliveTimeout = 5-15\nMaxHandshakeAttempts = 15-20");
Check(AmneziaWgConfig.Parse(smallHeaders).Text.Contains("H1 = 1"),"AmneziaWG native export accepts small packet headers");
Check(!WireGuardConfig.Parse(input.Replace("0.0.0.0/0","10.0.0.0/8")).FullTunnel,"split tunnel is identified honestly");
Check(WireGuardConfig.Parse(input.Replace("vpn.example.com:51820","[2001:db8::1]:51820")).Endpoint.StartsWith('['),"IPv6 endpoint accepted");
var realityLink="vless://5783a3e7-e373-51cd-8642-c83782b807c5@vpn.example.com:443?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcd#Amsterdam";
var reality=XrayNode.Parse(realityLink);
Check(reality.Name=="Amsterdam" && reality.Network=="raw" && reality.Port==443,"VLESS REALITY subscription link parsed");
Check(reality.Build().Contains("autoSystemRoutingTable") && reality.Build().Contains("local-http"),"Xray config includes tunnel and browser proxy");
Check(reality.Build().Contains("\"password\"") && !reality.Build().Contains("\"publicKey\""),"XRay REALITY uses current client key setting");
var secondNode=XrayNode.Parse(realityLink.Replace("vpn.example.com:443","other.example.com:443").Replace("#Amsterdam","#Rotterdam"));
var subscriptionUrl="https://sub.example.com/private-token";
var subscriptions=new ProfileData { SelectedId="second", Profiles=[
    new Profile("own","My VPS",input,"vpn.example.com:51820",true),
    new Profile("first",reality.Name,reality.Link,reality.Endpoint,true,subscriptionUrl),
    new Profile("second",secondNode.Name,secondNode.Link,secondNode.Endpoint,true,subscriptionUrl)] };
var grouped=ConnectionCatalog.Entries(subscriptions);
Check(grouped.Count==2 && grouped[1].IsSelected && grouped[1].Description.Contains("2 сервера") && !grouped[1].Name.Contains("private-token"),"subscription appears as one private group with a selected node");
var refreshedSubscription=ConnectionCatalog.MergeSubscription(subscriptions,subscriptionUrl,[reality,secondNode],false);
Check(refreshedSubscription.SelectedId=="second" && refreshedSubscription.Profiles.Count==3,"refresh preserves the selected server and other connections");
var removedNode=ConnectionCatalog.MergeSubscription(refreshedSubscription,subscriptionUrl,[reality],false);
Check(removedNode.SelectedId=="first" && removedNode.Profiles.Count==2,"refresh selects a remaining server when a node disappears");
var xrayExe=Path.Combine(Directory.GetCurrentDirectory(),"vendor","xray-26.9.9","bin","xray.exe");
if(File.Exists(xrayExe))
{
    var xrayConfigPath=Path.Combine(Path.GetTempPath(),"HateVPN-xray-test-"+Guid.NewGuid().ToString("N")+".json");
    try
    {
        File.WriteAllText(xrayConfigPath,reality.Build());
        var start=new ProcessStartInfo(xrayExe) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
        start.ArgumentList.Add("run"); start.ArgumentList.Add("-test"); start.ArgumentList.Add("-config"); start.ArgumentList.Add(xrayConfigPath);
        using var process=Process.Start(start) ?? throw new Exception("Could not start XRay config validation");
        if(!process.WaitForExit(10000)) { process.Kill(); throw new Exception("XRay config validation timed out"); }
        Check(process.ExitCode==0,"current XRay accepts generated Windows tunnel configuration");
    }
    finally { File.Delete(xrayConfigPath); }
}
bool rejectedPlaceholder=false; try { XrayNode.Parse(realityLink.Replace("vpn.example.com:443","0.0.0.0:1")); } catch(FormatException) { rejectedPlaceholder=true; }
Check(rejectedPlaceholder,"provider placeholder is rejected");
var now=DateTime.UtcNow;
Check(ConnectionHealth.Classify(null,now.AddSeconds(-5),now)=="connecting","no handshake is never connected");
Check(ConnectionHealth.Classify(null,now.AddMinutes(-1),now)=="reconnecting","unreachable peer reports retry");
Check(ConnectionHealth.Classify(now.AddSeconds(-2),now.AddMinutes(-1),now)=="connected","recent authenticated handshake is connected");
Check(ConnectionHealth.Classify(now.AddMinutes(-4),now.AddMinutes(-10),now)=="reconnecting","stale handshake is not connected");
Check(ConnectionHealth.Classify(now.AddHours(1),now,now)!="connected","future clock anomaly is not connected");
Check(ConnectionHealth.ClassifyTraffic(now.AddSeconds(-2),now.AddMinutes(-1),now,92,17150529)=="no-data","handshake without inbound payload is not healthy");
Check(ConnectionHealth.ClassifyTraffic(now.AddSeconds(-2),now.AddMinutes(-1),now,2048,17150529)=="connected","bidirectional traffic remains healthy");

var directory=Path.Combine(Path.GetTempPath(),"HateVPN-tests-"+Guid.NewGuid().ToString("N"));
try
{
    var store=new ProfileStore(directory); var data=new ProfileData();
    var profile=new Profile(Guid.NewGuid().ToString(),"Test",parsed.Text,parsed.Endpoint,true);
    data.Profiles.Add(profile); data.SelectedId=profile.Id; store.Save(data);
    var ciphertext=File.ReadAllBytes(Path.Combine(directory,"profiles.v1.bin"));
    Check(!Encoding.UTF8.GetString(ciphertext).Contains(key),"private key is absent from storage ciphertext");
    var restored=store.Load(); Check(restored.Profiles.Single().Config==parsed.Text && restored.SelectedId==profile.Id,"encrypted store survives restart");
    ciphertext[^1]^=1; File.WriteAllBytes(Path.Combine(directory,"profiles.v1.bin"),ciphertext);
    bool failed=false; try { store.Load(); } catch(CryptographicException) { failed=true; }
    Check(failed,"tampered store rejected");
    Check(profile.ToString()=="Test","profile ToString does not reveal secrets");
}
finally
{
    var resolved=Path.GetFullPath(directory);
    var tempRoot=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
    if(Path.GetDirectoryName(resolved)!=tempRoot || !Path.GetFileName(resolved).StartsWith("HateVPN-tests-",StringComparison.Ordinal)) throw new IOException("Unsafe test cleanup path.");
    if(Directory.Exists(resolved)) Directory.Delete(resolved,true);
}

using(var stream=new MemoryStream())
{
    await Protocol.WriteAsync(stream,new Request("connect",parsed.Text,"test"),CancellationToken.None); stream.Position=0;
    Check((await Protocol.ReadAsync<Request>(stream,CancellationToken.None)).Config==parsed.Text,"bounded IPC round trip");
}
using(var stream=new MemoryStream(BitConverter.GetBytes(65537)))
{
    bool rejected=false; try { await Protocol.ReadAsync<Request>(stream,CancellationToken.None); } catch(InvalidDataException) { rejected=true; }
    Check(rejected,"oversized IPC frame rejected before allocation");
}
using(var stream=new MemoryStream([4,0,0,0,1]))
{
    bool rejected=false; try { await Protocol.ReadAsync<Request>(stream,CancellationToken.None); } catch(EndOfStreamException) { rejected=true; }
    Check(rejected,"truncated IPC fails without hanging");
}
using(var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(8)))
{
    var name="HateVPN.Test."+Guid.NewGuid().ToString("N");
    using var server=LocalControlPipe.Create(name);
    bool secondRejected=false;
    try { using var duplicate=LocalControlPipe.Create(name); }
    catch(IOException) { secondRejected=true; }
    catch(UnauthorizedAccessException) { secondRejected=true; }
    Check(secondRejected,"control pipe rejects a second server instance");
    var serving=Task.Run(async()=>
    {
        await server.WaitForConnectionAsync(timeout.Token);
        await Protocol.ReadAsync<Request>(server,timeout.Token);
        var sid=LocalControlPipe.ClientSid(server);
        await Protocol.WriteAsync(server,new Response(true,Error:sid),timeout.Token);
    });
    using var client=new System.IO.Pipes.NamedPipeClientStream(".",name,System.IO.Pipes.PipeDirection.InOut,System.IO.Pipes.PipeOptions.Asynchronous,System.Security.Principal.TokenImpersonationLevel.Identification);
    await client.ConnectAsync(timeout.Token);
    await Protocol.WriteAsync(client,new Request("status"),timeout.Token);
    var reply=await Protocol.ReadAsync<Response>(client,timeout.Token);
    await serving;
    Check(reply.Error==System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value,"real named-pipe IPC authenticates caller SID");
}
Console.WriteLine($"{count} checks passed.");
