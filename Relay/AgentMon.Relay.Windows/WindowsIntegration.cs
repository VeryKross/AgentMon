using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AgentMon.Relay.Windows;

internal static class WindowsIntegration
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string StartupValueName = "AgentMon Relay";
    private const string FirewallRuleName = "AgentMon Relay (Private network only)";
    private const string LocalSubnet = "LocalSubnet";
    private const int RelayPort = 47831;
    private const int PrivateProfile = 2;
    private const int PublicProfile = 4;
    private const int InboundDirection = 1;
    private const int AllowAction = 1;
    private const int TcpProtocol = 6;

    internal enum FirewallStatus
    {
        NotConfigured,
        Configured,
        UnsafeRulePresent,
        Unavailable,
    }

    internal static bool IsStartupEnabled()
    {
        var expected = BuildStartupCommand();
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
        return string.Equals(
            key?.GetValue(StartupValueName) as string,
            expected,
            StringComparison.Ordinal);
    }

    internal static void SetStartupEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
        if (enabled)
        {
            key.SetValue(StartupValueName, BuildStartupCommand(), RegistryValueKind.String);
        }
        else
        {
            key.DeleteValue(StartupValueName, throwOnMissingValue: false);
        }
    }

    internal static FirewallStatus GetPrivateFirewallStatus()
    {
        object? policy = null;
        object? rules = null;
        try
        {
            policy = CreateComObject("HNetCfg.FwPolicy2");
            rules = ((dynamic)policy).Rules;

            foreach (var rule in (System.Collections.IEnumerable)rules)
            {
                try
                {
                    if (!string.Equals(
                            (string)((dynamic)rule).Name,
                            FirewallRuleName,
                            StringComparison.Ordinal))
                    {
                        continue;
                    }

                    var profiles = (int)((dynamic)rule).Profiles;
                    if ((profiles & PublicProfile) != 0)
                    {
                        return FirewallStatus.UnsafeRulePresent;
                    }

                    return RuleMatches((dynamic)rule)
                        ? FirewallStatus.Configured
                        : FirewallStatus.NotConfigured;
                }
                finally
                {
                    ReleaseComObject(rule);
                }
            }

            return FirewallStatus.NotConfigured;
        }
        catch (COMException)
        {
            return FirewallStatus.Unavailable;
        }
        finally
        {
            ReleaseComObject(rules);
            ReleaseComObject(policy);
        }
    }

    internal static async Task<bool> ConfigurePrivateFirewallRuleElevatedAsync()
    {
        var executablePath = GetInstalledExecutablePath();
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = executablePath,
            Arguments = "--configure-firewall",
            UseShellExecute = true,
            Verb = "runas",
            WindowStyle = ProcessWindowStyle.Hidden,
        });

        if (process is null)
        {
            return false;
        }

        await process.WaitForExitAsync();
        return process.ExitCode == 0;
    }

    internal static void ConfigurePrivateFirewallRule()
    {
        var executablePath = GetInstalledExecutablePath();
        object? policy = null;
        object? rules = null;
        object? newRule = null;
        object? existingRule = null;

        try
        {
            policy = CreateComObject("HNetCfg.FwPolicy2");
            rules = ((dynamic)policy).Rules;

            foreach (var rule in (System.Collections.IEnumerable)rules)
            {
                if (string.Equals(
                        (string)((dynamic)rule).Name,
                        FirewallRuleName,
                        StringComparison.Ordinal))
                {
                    existingRule = rule;
                    var profiles = (int)((dynamic)rule).Profiles;
                    if ((profiles & PublicProfile) != 0)
                    {
                        throw new InvalidOperationException("A public-profile rule with the reserved name exists.");
                    }

                    break;
                }

                ReleaseComObject(rule);
            }

            if (existingRule is not null)
            {
                ((dynamic)rules).Remove(FirewallRuleName);
            }

            newRule = CreateComObject("HNetCfg.FWRule");
            dynamic configuredRule = newRule;
            configuredRule.Name = FirewallRuleName;
            configuredRule.Description = "Allows AgentMon Relay from devices on the local private subnet.";
            configuredRule.ApplicationName = executablePath;
            configuredRule.Protocol = TcpProtocol;
            configuredRule.LocalPorts = RelayPort.ToString(System.Globalization.CultureInfo.InvariantCulture);
            configuredRule.RemoteAddresses = LocalSubnet;
            configuredRule.Direction = InboundDirection;
            configuredRule.Profiles = PrivateProfile;
            configuredRule.Action = AllowAction;
            configuredRule.Enabled = true;
            ((dynamic)rules).Add(configuredRule);
        }
        finally
        {
            ReleaseComObject(existingRule);
            ReleaseComObject(newRule);
            ReleaseComObject(rules);
            ReleaseComObject(policy);
        }
    }

    internal static void OpenLogDirectory()
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = RelayApplication.LogDirectory,
            UseShellExecute = true,
        });
    }

    private static bool RuleMatches(dynamic rule)
    {
        return (bool)rule.Enabled &&
               (int)rule.Direction == InboundDirection &&
               (int)rule.Action == AllowAction &&
               (int)rule.Protocol == TcpProtocol &&
               (int)rule.Profiles == PrivateProfile &&
               string.Equals((string)rule.ApplicationName, GetInstalledExecutablePath(), StringComparison.OrdinalIgnoreCase) &&
               string.Equals((string)rule.LocalPorts, RelayPort.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal) &&
               string.Equals((string)rule.RemoteAddresses, LocalSubnet, StringComparison.OrdinalIgnoreCase);
    }

    private static string BuildStartupCommand()
    {
        return $"\"{GetInstalledExecutablePath()}\" --background";
    }

    private static string GetInstalledExecutablePath()
    {
        var path = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(path) ||
            !string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(Path.GetFileName(path), "dotnet.exe", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("This operation requires the installed AgentMon Relay application.");
        }

        return Path.GetFullPath(path);
    }

    private static object CreateComObject(string programmaticIdentifier)
    {
        var type = Type.GetTypeFromProgID(programmaticIdentifier, throwOnError: true)
            ?? throw new COMException("Windows Firewall is unavailable.");
        return Activator.CreateInstance(type)
            ?? throw new COMException("Windows Firewall is unavailable.");
    }

    private static void ReleaseComObject(object? value)
    {
        if (value is not null && Marshal.IsComObject(value))
        {
            Marshal.FinalReleaseComObject(value);
        }
    }
}
