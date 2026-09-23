using System.Security.Principal;

namespace AgentMon.Relay.Windows;

internal static class InstallationMaintenance
{
    internal static string Version => typeof(Program).Assembly.GetName().Version?.ToString(3)
        ?? throw new InvalidOperationException("Application version is unavailable.");

    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] is not
            ("--version" or "--shutdown" or "--check-not-running" or "--uninstall-cleanup" or "--remove-firewall" or "--remove-user-data"))
            return false;

        try
        {
            if (args.Length != 1 && !(args.Length == 2 && args[0] == "--uninstall-cleanup" && args[1] == "--silent"))
                throw new ArgumentException("Invalid maintenance arguments.");
            if (args[0] == "--version")
            {
                Console.WriteLine(Version);
                return true;
            }
            if (args[0] == "--remove-firewall")
            {
                WindowsIntegration.RemoveOwnedPrivateFirewallRule();
                return true;
            }
            if (args[0] == "--shutdown")
            {
                if (!Mutex.TryOpenExisting(Program.InstanceMutexName, out var running))
                    return true;
                using (running)
                using (var shutdown = EventWaitHandle.OpenExisting(Program.ShutdownEventName))
                {
                    shutdown.Set();
                    try
                    {
                        if (!running.WaitOne(TimeSpan.FromSeconds(20)))
                            throw new TimeoutException("The relay did not stop.");
                    }
                    catch (AbandonedMutexException)
                    {
                        // Process exit releases the lifetime mutex without an explicit ReleaseMutex.
                    }
                    running.ReleaseMutex();
                }
                return true;
            }

            using var mutex = new Mutex(true, Program.InstanceMutexName, out var ownsMutex);
            if (!ownsMutex)
                throw new InvalidOperationException("Quit AgentMon Relay from its tray menu first.");

            switch (args[0])
            {
                case "--uninstall-cleanup":
                    if (WindowsIntegration.HasOwnedPrivateFirewallRule())
                    {
                        using var identity = WindowsIdentity.GetCurrent();
                        var administrator = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
                        if (administrator)
                            WindowsIntegration.RemoveOwnedPrivateFirewallRule();
                        else if (args.Length == 2 || !WindowsIntegration.RemovePrivateFirewallRuleElevated())
                            throw new InvalidOperationException("Private firewall removal requires administrator approval.");
                    }
                    WindowsIntegration.RemoveOwnedStartupEntry();
                    break;
                case "--remove-user-data":
                    DeleteDataDirectory(RelayApplication.DataDirectory);
                    break;
            }
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // Maintenance must not recreate deleted logs or emit pairing material.
            Console.Error.WriteLine($"AgentMon Relay maintenance failed ({error.GetType().Name}).");
            exitCode = 1;
        }
        return true;
    }

    internal static void DeleteDataDirectory(string directory)
    {
        if (!Directory.Exists(directory))
            return;

        var pending = new Stack<string>();
        pending.Push(directory);
        while (pending.TryPop(out var current))
        {
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Refusing to remove redirected relay data.");
            foreach (var entry in Directory.EnumerateFileSystemEntries(current))
            {
                var attributes = File.GetAttributes(entry);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Refusing to remove redirected relay data.");
                if ((attributes & FileAttributes.Directory) != 0)
                    pending.Push(entry);
            }
        }
        Directory.Delete(directory, recursive: true);
    }
}
