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

    internal static string Activity(ReadOnlyMemory<byte> tail, bool live, DateTimeOffset updatedAt, DateTimeOffset now,
        bool hasAvailableWorkspace = false, bool hasActiveDescendant = false)
    {
        var recent = now - updatedAt < TimeSpan.FromMinutes(15);

        var completed = new HashSet<string>(StringComparer.Ordinal);
        var assistantTurnEnded = false;
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
                if (IsTurnCompletion(root, type))
                    return live ? hasActiveDescendant ? "working" : "ready" : "offline";
                if (type is "session.fusion_commit_started" or "session.fusion_handoff" ||
                    type?.StartsWith("model.", StringComparison.Ordinal) == true)
                    return live ? recent ? "working" : "ready" : "offline";
                if (type == "tool.execution_complete" && root.TryGetProperty("data", out var finished))
                {
                    if (StringProperty(finished, "toolCallId") is { } completedId)
                        completed.Add(completedId);
                }
                else if (type == "hook.start" && root.TryGetProperty("data", out var hookStart) &&
                         StringProperty(hookStart, "hookType") == "preToolUse" &&
                         TryGetToolCalls(hookStart, out var toolCalls))
                {
                    if (ContainsUnexecutedAskUserCall(toolCalls, completed))
                        return live || hasAvailableWorkspace ? "attention" : "offline";
                    return live ? recent ? "working" : "ready" : "offline";
                }
                else if (type == "tool.execution_start" && root.TryGetProperty("data", out var started) &&
                         StringProperty(started, "toolName") == "ask_user" &&
                         StringProperty(started, "toolCallId") is { } questionId && !completed.Contains(questionId) &&
                         !assistantTurnEnded)
                {
                    return live || hasAvailableWorkspace ? "attention" : "offline";
                }
                else if (type == "assistant.turn_start")
                {
                    if (!assistantTurnEnded)
                        return live ? recent ? "working" : "ready" : "offline";
                }
                else if (type == "assistant.turn_end")
                    assistantTurnEnded = true;
                else if (type == "user.message")
                    return assistantTurnEnded ? live ? "ready" : "offline" :
                        live ? recent ? "working" : "ready" : "offline";
            }
            catch (JsonException)
            {
                // Copilot can be in the middle of writing a line; no event contents are logged.
            }
        }
        return live ? hasActiveDescendant ? "working" : "ready" : "offline";
    }

    private static bool IsTurnCompletion(JsonElement root, string? type)
        => type == "session.fusion_completed" ||
           type == "hook.end" && root.TryGetProperty("data", out var data) &&
           data.ValueKind == JsonValueKind.Object &&
           data.TryGetProperty("success", out var success) && success.ValueKind == JsonValueKind.True &&
           StringProperty(data, "hookType") is "agentStop" or "sessionEnd";

    private static string? StringProperty(JsonElement element, string name)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) &&
           value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static bool TryGetToolCalls(JsonElement hook, out JsonElement calls)
    {
        calls = default;
        if (!hook.TryGetProperty("input", out var input) || input.ValueKind != JsonValueKind.Object ||
            !input.TryGetProperty("toolCalls", out calls) || calls.ValueKind != JsonValueKind.Array ||
            calls.GetArrayLength() == 0)
            return false;
        return true;
    }

    private static bool ContainsUnexecutedAskUserCall(JsonElement calls, HashSet<string> completed)
    {
        return calls.EnumerateArray().Any(call =>
            StringProperty(call, "name") == "ask_user" &&
            StringProperty(call, "id") is { } id &&
            !completed.Contains(id));
    }
}
