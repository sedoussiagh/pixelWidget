using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        try
        {
            var folder = AppDomain.CurrentDomain.BaseDirectory;
            var script = Path.Combine(folder, "PixelMonitor.ps1");
            var shell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            Process.Start(new ProcessStartInfo(shell,
                "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"")
            {
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true
            });
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Pixel Monitor", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
