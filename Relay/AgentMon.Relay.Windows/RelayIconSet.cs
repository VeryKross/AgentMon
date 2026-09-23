using System.Reflection;

namespace AgentMon.Relay.Windows;

internal enum RelayIconState
{
    Stopped,
    Running,
    Waiting,
    Error,
}

internal sealed class RelayIconSet : IDisposable
{
    private const string ResourcePrefix = "AgentMon.Relay.Windows.Assets.AgentMonRelay";
    private readonly Dictionary<RelayIconState, (MemoryStream Stream, Icon Icon)> icons = [];
    private bool disposed;

    private RelayIconSet()
    {
        try
        {
            foreach (var state in Enum.GetValues<RelayIconState>())
            {
                icons.Add(state, LoadIcon(state));
            }
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal Icon this[RelayIconState state]
    {
        get
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            return icons[state].Icon;
        }
    }

    internal static RelayIconSet Load() => new();

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        foreach (var resource in icons.Values)
        {
            resource.Icon.Dispose();
            resource.Stream.Dispose();
        }

        icons.Clear();
    }

    private static (MemoryStream Stream, Icon Icon) LoadIcon(RelayIconState state)
    {
        var resourceName = $"{ResourcePrefix}.{state}.ico";
        using var resourceStream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Embedded Relay icon resource '{resourceName}' was not found.");
        var retainedStream = new MemoryStream();
        resourceStream.CopyTo(retainedStream);
        retainedStream.Position = 0;

        try
        {
            return (retainedStream, new Icon(retainedStream));
        }
        catch
        {
            retainedStream.Dispose();
            throw;
        }
    }
}
