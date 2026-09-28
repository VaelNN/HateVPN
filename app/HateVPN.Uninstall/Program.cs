using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

namespace HateVPN.Uninstall
{
    internal static class Program
    {
        private const string UpgradeCode = "{ED1E499C-910E-4EF0-8A73-FFB03843607A}";

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiEnumRelatedProducts(string upgradeCode, uint reserved, uint index, StringBuilder productCode);

        [STAThread]
        private static void Main()
        {
            try
            {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"Software\HateVPN"))
                {
                    string installedPath = key == null ? null : key.GetValue("InstallPath") as string;
                    if (String.IsNullOrWhiteSpace(installedPath) ||
                        !String.Equals(Path.GetFullPath(installedPath).TrimEnd('\\'),
                            Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory).TrimEnd('\\'),
                            StringComparison.OrdinalIgnoreCase))
                    {
                        MessageBox.Show("Запустите удаление из папки установленного HateVPN.", "HateVPN", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return;
                    }
                }

                StringBuilder productCode = new StringBuilder(39);
                Guid parsedProductCode;
                if (MsiEnumRelatedProducts(UpgradeCode, 0, 0, productCode) != 0 || !Guid.TryParse(productCode.ToString(), out parsedProductCode))
                {
                    MessageBox.Show("Установка HateVPN не найдена. Проверьте список приложений Windows.", "HateVPN", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                if (MessageBox.Show("Удалить HateVPN, сохранённые профили, настройки и журналы?", "Удаление HateVPN",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                    return;

                Process.Start(new ProcessStartInfo("msiexec.exe", "/x " + productCode + " /norestart")
                {
                    UseShellExecute = true,
                    Verb = "runas"
                });
            }
            catch (Win32Exception ex)
            {
                if (ex.NativeErrorCode != 1223)
                    MessageBox.Show("Не удалось запустить удаление: " + ex.Message, "HateVPN", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Не удалось запустить удаление: " + ex.Message, "HateVPN", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
