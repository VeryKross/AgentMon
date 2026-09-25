using System.Security.Principal;

namespace AgentMon.Relay.Windows;

internal static class Program
{
    private const string ConfigureFirewallArgument = "--configure-firewall";
    private const string BackgroundArgument = "--background";
    internal static string InstanceMutexName => $"Local\\AgentMonRelay-{GetCurrentUserSid()}";
    internal static string ShutdownEventName => $"Local\\AgentMonRelay-Quit-{GetCurrentUserSid()}";

    [STAThread]
    private static int Main(string[] args)
    {
        if (InstallationMaintenance.TryRun(args, out var exitCode))
        {
            return exitCode;
        }

        if (args.Length == 1 &&
            string.Equals(args[0], ConfigureFirewallArgument, StringComparison.OrdinalIgnoreCase))
        {
            return ConfigureFirewall();
        }

        ApplicationConfiguration.Initialize();

        using var mutex = new Mutex(
            initiallyOwned: true,
            InstanceMutexName,
            out var ownsMutex);

        if (!ownsMutex)
        {
            MessageBox.Show(
                "AgentMon Relay is already running for this Windows user. Use its notification-area icon to open it.",
                "AgentMon Relay",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return 0;
        }

        try
        {
            var controller = RelayApplication.CreateController();
            var startInBackground = ShouldStartInBackground(args, controller.StartHidden);
            using var context = new RelayTrayContext(
                controller,
                startInBackground);
            Application.Run(context);
            return 0;
        }
        catch (Exception error)
        {
            RelayApplication.LogFailure("application startup", error);
            MessageBox.Show(
                $"AgentMon Relay could not start ({error.GetType().Name}).",
                "AgentMon Relay",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    internal static bool ShouldStartInBackground(string[] args, bool startHidden)
        => startHidden || args.Any(argument =>
            string.Equals(argument, BackgroundArgument, StringComparison.OrdinalIgnoreCase));

    private static int ConfigureFirewall()
    {
        try
        {
            WindowsIntegration.ConfigurePrivateFirewallRule();
            return 0;
        }
        catch (Exception error)
        {
            RelayApplication.LogFailure("firewall configuration", error);
            return 1;
        }
    }

    private static string GetCurrentUserSid()
    {
        return WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
    }
}
