using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class InstallationTests
{
    [TestMethod]
    public void FirewallRemoval_RequiresEveryOwnedRuleRestriction()
    {
        const string path = @"C:\Installed\AgentMonRelay.exe";
        var exact = new WindowsIntegration.FirewallRuleConfiguration(true, 1, 1, 6, 2, path, "47831", "LocalSubnet");
        Assert.IsTrue(WindowsIntegration.FirewallRuleMatches(exact, path, false));
        Assert.IsTrue(WindowsIntegration.FirewallRuleMatches(exact with { Enabled = false }, path, false));
        Assert.IsFalse(WindowsIntegration.FirewallRuleMatches(exact with { Enabled = false }, path, true));
        var unrelated = new[]
        {
            exact with { Direction = 2 }, exact with { Action = 0 }, exact with { Protocol = 17 },
            exact with { Profiles = 4 }, exact with { Profiles = 6 },
            exact with { ApplicationName = @"C:\Other\AgentMonRelay.exe" },
            exact with { LocalPorts = "*" }, exact with { RemoteAddresses = "*" },
        };
        foreach (var rule in unrelated)
            Assert.IsFalse(WindowsIntegration.FirewallRuleMatches(rule, path, false));
    }

    [TestMethod]
    public void StartupRemoval_OnlyMatchesTheExactInstalledCommand()
    {
        const string executable = @"C:\Users\Test\AppData\Local\Programs\AgentMonRelay\AgentMonRelay.exe";
        Assert.IsTrue(WindowsIntegration.StartupCommandMatches($"\"{executable}\" --background", executable));
        Assert.IsFalse(WindowsIntegration.StartupCommandMatches(null, executable));
        Assert.IsFalse(WindowsIntegration.StartupCommandMatches("\"C:\\Other\\AgentMonRelay.exe\" --background", executable));
        Assert.IsFalse(WindowsIntegration.StartupCommandMatches($"\"{executable}\" --unexpected", executable));
    }

    [TestMethod]
    public void LaunchMode_FirstLaunchShowsWindowAndSignInOrPreferenceHidesIt()
    {
        Assert.IsFalse(Program.ShouldStartInBackground([], startHidden: false));
        Assert.IsTrue(Program.ShouldStartInBackground([], startHidden: true));
        Assert.IsTrue(Program.ShouldStartInBackground(["--background"], startHidden: false));
        Assert.IsTrue(Program.ShouldStartInBackground(["--BACKGROUND"], startHidden: false));
    }

    [TestMethod]
    public void VersionCommand_ReturnsWithoutCreatingState()
    {
        Assert.IsTrue(InstallationMaintenance.TryRun(["--version"], out var code));
        Assert.AreEqual(0, code);
        Assert.IsTrue(System.Version.TryParse(InstallationMaintenance.Version, out _));
        Assert.IsTrue(InstallationMaintenance.TryRun(["--version", "--extra"], out code));
        Assert.AreEqual(1, code);
        Assert.IsFalse(InstallationMaintenance.TryRun(["--background"], out _));
    }

    [TestMethod]
    public void RunningInstance_BlocksMaintenance()
    {
        var name = $"Local\\AgentMonRelay-Test-{Guid.NewGuid():N}";
        using var mutex = new Mutex(true, name, out var owned);
        Assert.IsTrue(owned);
        Assert.IsTrue(InstallationMaintenance.TryRun(["--check-not-running"], out var code, name));
        Assert.AreEqual(1, code);
        Assert.IsTrue(InstallationMaintenance.TryRun(["--remove-user-data"], out code, name));
        Assert.AreEqual(1, code);
    }

    [TestMethod]
    public void ExplicitDataRemoval_LeavesSiblingDataIntact()
    {
        using var temp = new TestDirectory();
        var data = temp.FilePath("relay");
        Directory.CreateDirectory(Path.Combine(data, "Logs"));
        File.WriteAllText(Path.Combine(data, "settings.dpapi"), "synthetic-protected-settings");
        File.WriteAllText(Path.Combine(data, "Logs", "relay.log"), "synthetic-log");
        var unrelated = temp.FilePath("unrelated.txt");
        File.WriteAllText(unrelated, "keep");
        InstallationMaintenance.DeleteDataDirectory(data);
        Assert.IsFalse(Directory.Exists(data));
        Assert.AreEqual("keep", File.ReadAllText(unrelated));
        InstallationMaintenance.DeleteDataDirectory(data);
    }

    [TestMethod]
    public void ExplicitDataRemoval_RejectsJunctionWithoutTouchingTarget()
    {
        using var temp = new TestDirectory();
        var data = temp.FilePath("relay");
        var other = temp.FilePath("unrelated");
        Directory.CreateDirectory(data);
        Directory.CreateDirectory(other);
        var sentinel = Path.Combine(other, "keep.txt");
        File.WriteAllText(sentinel, "keep");
        var junction = Path.Combine(data, "redirect");
        var start = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -NonInteractive -Command \"New-Item -ItemType Junction -Path '{junction}' -Target '{other}' | Out-Null\"",
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        start.Environment.Remove("PSModulePath");
        using var process = System.Diagnostics.Process.Start(start)!;
        try
        {
            if (!process.WaitForExit(60000))
            {
                process.Kill(entireProcessTree: true);
                Assert.IsTrue(process.WaitForExit(10000), "Junction fixture process did not terminate.");
                Assert.Fail("Junction fixture creation timed out.");
            }
            Assert.AreEqual(0, process.ExitCode, "Junction fixture creation failed.");
            Assert.ThrowsExactly<IOException>(() => InstallationMaintenance.DeleteDataDirectory(data));
            Assert.AreEqual("keep", File.ReadAllText(sentinel));
        }
        finally
        {
            if (Directory.Exists(junction))
                Directory.Delete(junction);
        }
    }
}
