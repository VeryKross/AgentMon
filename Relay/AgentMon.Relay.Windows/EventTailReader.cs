using System.Text.Json;

namespace AgentMon.Relay.Windows;

internal static class EventTailReader
{
    internal const int MaximumBytes = 128 * 1024;

    internal static byte[] Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var length = stream.Length;
        var offset = Math.Max(0, length - MaximumBytes);
        stream.Position = offset;
        var buffer = new byte[checked((int)(length - offset))];
        stream.ReadExactly(buffer);
        // Never parse a fragment whose start fell outside the bounded tail.
        if (offset > 0)
        {
            var newline = Array.IndexOf(buffer, (byte)'\n');
            return newline < 0 ? [] : buffer[(newline + 1)..];
        }
        return buffer;
    }

    internal static string Activity(ReadOnlyMemory<byte> tail, bool live, DateTimeOffset updatedAt, DateTimeOffset now)
    {
        if (!live)
            return "offline";
        var recent = now - updatedAt < TimeSpan.FromMinutes(15);

        var completed = new HashSet<string>(StringComparer.Ordinal);
        var end = tail.Length;
        while (end > 0)
        {
            var start = tail.Span[..end].LastIndexOf((byte)'\n') + 1;
            var line = tail[start..end];
            end = start == 0 ? 0 : start - 1;
            if (line.IsEmpty)
                continue;
            try
            {
                using var document = JsonDocument.Parse(line, new JsonDocumentOptions { MaxDepth = 64 });
                var root = document.RootElement;
                var type = StringProperty(root, "type");
                if (type == "tool.execution_complete" && root.TryGetProperty("data", out var finished))
                {
                    if (StringProperty(finished, "toolCallId") is { } completedId)
                        completed.Add(completedId);
                }
                else if (type == "tool.execution_start" && root.TryGetProperty("data", out var started) &&
                         StringProperty(started, "toolName") == "ask_user" &&
                         StringProperty(started, "toolCallId") is { } questionId && !completed.Contains(questionId))
                {
                    return "attention";
                }
                else if (type == "assistant.turn_start")
                    return recent ? "working" : "ready";
                else if (type == "assistant.turn_end")
                    return "ready";
            }
            catch (JsonException)
            {
                // Copilot can be in the middle of writing a line; no event contents are logged.
            }
        }
        return "ready";
    }

    private static string? StringProperty(JsonElement element, string name)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) &&
           value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
