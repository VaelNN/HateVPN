/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2019-2026 WireGuard LLC. All Rights Reserved.
 */

using System;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Diagnostics;
using System.Threading;

namespace Tunnel
{
    public class Service
    {
        private const string LongName = "HateVPN";
        private const string Description = "HateVPN encrypted tunnel";

        [DllImport("tunnel.dll", EntryPoint = "WireGuardTunnelService", CallingConvention = CallingConvention.Cdecl)]
        public static extern bool Run([MarshalAs(UnmanagedType.LPWStr)] string configFile);
        [DllImport("amneziawg-tunnel.dll", EntryPoint = "WireGuardTunnelService", CallingConvention = CallingConvention.Cdecl)]
        public static extern bool RunAmnezia([MarshalAs(UnmanagedType.LPWStr)] string config, [MarshalAs(UnmanagedType.LPWStr)] string name);

        public static Driver.Adapter GetAdapter(string configFile)
        {
            return new Driver.Adapter("HateVPN");
        }

        public static void Add(string configFile, bool ephemeral, bool amnezia = false)
        {
            var tunnelName = amnezia ? "HateVPNAWG" : "HateVPN";
            var shortName = amnezia ? tunnelName : String.Format("WireGuardTunnel${0}", tunnelName);
            var longName = String.Format("{0}: {1}", LongName, tunnelName);
            var exeName = Process.GetCurrentProcess().MainModule.FileName;
            var pathAndArgs = String.Format("\"{0}\" {3} \"{1}\" {2}", exeName, configFile, Process.GetCurrentProcess().Id, amnezia ? "/awgservice" : "/service");

            var scm = Win32.OpenSCManager(null, null, Win32.ScmAccessRights.AllAccess);
            if (scm == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                var service = Win32.OpenService(scm, shortName, Win32.ServiceAccessRights.AllAccess);
                if (service != IntPtr.Zero)
                {
                    Win32.CloseServiceHandle(service);
                    Remove(configFile, true, amnezia);
                }
                service = Win32.CreateService(scm, shortName, longName, Win32.ServiceAccessRights.AllAccess, Win32.ServiceType.Win32OwnProcess, Win32.ServiceStartType.Demand, Win32.ServiceError.Normal, pathAndArgs, null, IntPtr.Zero, "Nsi\0TcpIp\0", null, null);
                if (service == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                try
                {
                    var sidType = Win32.ServiceSidType.Unrestricted;
                    if (!Win32.ChangeServiceConfig2(service, Win32.ServiceConfigType.SidInfo, ref sidType))
                        throw new Win32Exception(Marshal.GetLastWin32Error());

                    var description = new Win32.ServiceDescription { lpDescription = Description };
                    if (!Win32.ChangeServiceConfig2(service, Win32.ServiceConfigType.Description, ref description))
                        throw new Win32Exception(Marshal.GetLastWin32Error());

                    if (!Win32.StartService(service, 0, null))
                        throw new Win32Exception(Marshal.GetLastWin32Error());

                    if (ephemeral && !Win32.DeleteService(service))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                finally
                {
                    Win32.CloseServiceHandle(service);
                }
            }
            finally
            {
                Win32.CloseServiceHandle(scm);
            }
        }

        public static void Remove(string configFile, bool waitForStop, bool amnezia = false)
        {
            var shortName = amnezia ? "HateVPNAWG" : "WireGuardTunnel$HateVPN";

            var scm = Win32.OpenSCManager(null, null, Win32.ScmAccessRights.AllAccess);
            if (scm == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                var service = Win32.OpenService(scm, shortName, Win32.ServiceAccessRights.AllAccess);
                if (service == IntPtr.Zero)
                    return;
                try
                {
                    var serviceStatus = new Win32.ServiceStatus();
                    Win32.ControlService(service, Win32.ServiceControl.Stop, serviceStatus);

                    for (int i = 0; waitForStop && i < 15 && Win32.QueryServiceStatus(service, serviceStatus) && serviceStatus.dwCurrentState != Win32.ServiceState.Stopped; ++i)
                        Thread.Sleep(1000);

                    if (waitForStop && Win32.QueryServiceStatus(service, serviceStatus) && serviceStatus.dwCurrentState != Win32.ServiceState.Stopped)
                        throw new TimeoutException("The tunnel service did not stop in time.");

                    if (!Win32.DeleteService(service) && Marshal.GetLastWin32Error() != 0x00000430)
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                finally
                {
                    Win32.CloseServiceHandle(service);
                }
            }
            finally
            {
                Win32.CloseServiceHandle(scm);
            }
        }
    }
}

