using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using YamlDotNet.Core;

namespace AgentMon.Relay.Windows;

internal sealed class SessionIndexer(string root, SafeLog log, Func<int, bool>? isAlive = null)
{
    private RelaySnapshot? snapshot;
    private HashSet<string> knownWorkspaces = new(StringComparer.OrdinalIgnoreCase);
    private HashSet<string> knownEvents = new(StringComparer.OrdinalIgnoreCase);
    private bool rootSeen;
    internal RelaySnapshot? Snapshot => Volatile.Read(ref snapshot);
    internal bool LastScanFailed { get; private set; }

    // Called by one polling loop. Publish the whole scan atomically, never a mix of old and new timestamps.
    internal bool Scan(RelayHost host, DateTimeOffset now)
    {
        try
        {
            var sessions = new List<RelaySession>();
            var workspaces = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var events = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string[] directories;
            try
            {
                directories = Directory.GetDirectories(root);
                rootSeen = true;
            }
            catch (DirectoryNotFoundException) when (!rootSeen)
            {
                directories = [];
            }

            foreach (var directory in directories)
            {
                var info = new DirectoryInfo(directory);
                if (info.Name.StartsWith("pending-session", StringComparison.Ordinal) ||
                    info.Attributes.HasFlag(FileAttributes.ReparsePoint) ||
                    info.Attributes.HasFlag(FileAttributes.Hidden))
                    continue;
                var workspacePath = Path.Combine(directory, "workspace.yaml");
                var eventsPath = Path.Combine(directory, "events.jsonl");
                if (!File.Exists(workspacePath) && !knownWorkspaces.Contains(workspacePath))
                    continue;
                RejectReparsePoint(workspacePath);
                var fields = WorkspaceReader.Read(workspacePath);
                workspaces.Add(workspacePath);
                var workspaceDate = WorkspaceReader.UpdatedAt(fields) ?? File.GetLastWriteTimeUtc(workspacePath);
                var eventDate = DateTimeOffset.MinValue;
                byte[] tail = [];
                if (File.Exists(eventsPath) || knownEvents.Contains(eventsPath))
                {
                    RejectReparsePoint(eventsPath);
                    // Take the modification time before reading so a later append cannot freshen an older tail.
                    eventDate = File.GetLastWriteTimeUtc(eventsPath);
                    tail = EventTailReader.Read(eventsPath);
                    events.Add(eventsPath);
                }
                var updatedAt = workspaceDate > eventDate ? workspaceDate : eventDate;
                var live = HasLiveProcess(directory, isAlive ?? ProcessIsAlive);
                var activity = EventTailReader.Activity(tail, live, updatedAt, now);
                if (activity != "offline" || now - updatedAt < TimeSpan.FromDays(1))
                    sessions.Add(WorkspaceReader.Normalize(fields, updatedAt, activity));
            }
            var relevant = sessions.OrderBy(session => Rank(session.Activity))
                .ThenByDescending(session => session.UpdatedAt)
                .ThenBy(session => session.Id, StringComparer.Ordinal)
                .DistinctBy(session => session.Id).Take(50).ToArray();
            var result = new RelaySnapshot(RelaySnapshot.Version, RelaySnapshot.ApplicationVersion, now, host, relevant);
            knownWorkspaces = workspaces;
            knownEvents = events;
            Volatile.Write(ref snapshot, result);
            LastScanFailed = false;
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or YamlException or DecoderFallbackException)
        {
            log.Write(LogEvent.IndexFailed, ex);
            LastScanFailed = true;
            return false;
        }
    }

    internal static bool HasLiveProcess(string directory, Func<int, bool> isAlive)
    {
        foreach (var path in Directory.EnumerateFiles(directory, "inuse.*.lock", SearchOption.TopDirectoryOnly))
        {
            var name = Path.GetFileName(path);
            if (int.TryParse(name.AsSpan(6, name.Length - 11), out var pid) && pid > 0 && isAlive(pid))
                return true;
        }
        return false;
    }

    private static bool ProcessIsAlive(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 5)
        {
            return false;
        }
    }

    private static void RejectReparsePoint(string path)
    {
        if (File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint))
            throw new IOException("Session files must not be reparse points.");
    }

    private static int Rank(string activity) => activity switch
    {
        "attention" => 0, "working" => 1, "ready" => 2, _ => 3
    };
}
