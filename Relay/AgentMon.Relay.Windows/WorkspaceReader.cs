using System.Globalization;
using System.Text;
using YamlDotNet.Core;
using YamlDotNet.Core.Events;

namespace AgentMon.Relay.Windows;

internal static class WorkspaceReader
{
    internal const int MaximumBytes = 256 * 1024;
    private static readonly HashSet<string> AllowedKeys =
        ["id", "cwd", "repository", "branch", "name", "updated_at"];

    internal static Dictionary<string, string> Parse(string source)
    {
        var parser = new Parser(new StringReader(source));
        parser.Consume<StreamStart>();
        parser.Consume<DocumentStart>();
        parser.Consume<MappingStart>();
        var fields = new Dictionary<string, string>(StringComparer.Ordinal);
        while (!parser.TryConsume<MappingEnd>(out _))
        {
            var key = parser.Consume<Scalar>().Value;
            if (parser.TryConsume<Scalar>(out var value))
            {
                if (AllowedKeys.Contains(key) &&
                    !(value.Style == ScalarStyle.Plain && value.Value is "" or "~" or "null" or "Null" or "NULL"))
                {
                    if (!fields.TryAdd(key, value.Value))
                        throw new InvalidDataException("Duplicate workspace field.");
                }
            }
            else
            {
                parser.SkipThisAndNestedEvents();
            }
        }
        parser.Consume<DocumentEnd>();
        parser.Consume<StreamEnd>();
        if (!fields.TryGetValue("id", out var id) || string.IsNullOrWhiteSpace(id))
            throw new InvalidDataException("Missing workspace ID.");
        return fields;
    }

    internal static Dictionary<string, string> Read(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length > MaximumBytes)
            throw new InvalidDataException("Workspace exceeds size limit.");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        // A concurrent metadata rewrite is not a new successful index.
        if (stream.Length != bytes.Length)
            throw new IOException("Workspace changed during read.");
        return Parse(new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF'));
    }

    internal static RelaySession Normalize(Dictionary<string, string> fields, DateTimeOffset updatedAt, string activity)
    {
        fields.TryGetValue("repository", out var repository);
        fields.TryGetValue("branch", out var branch);
        var project = repository?.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
        if (string.IsNullOrWhiteSpace(project) && fields.TryGetValue("cwd", out var cwd))
            project = cwd.TrimEnd('\\', '/').Split('\\', '/').LastOrDefault();
        if (string.IsNullOrWhiteSpace(project))
            project = "Untitled Project";
        var name = fields.GetValueOrDefault("name", "Copilot session");
        var task = string.Join(' ', name.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        task = string.Concat(task.EnumerateRunes().Take(120).Select(rune => rune.ToString()));
        return new RelaySession(fields["id"], project, task, repository, branch, activity, updatedAt);
    }

    internal static DateTimeOffset? UpdatedAt(Dictionary<string, string> fields)
        => fields.TryGetValue("updated_at", out var text) &&
           DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture,
               DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var value)
            ? value : null;
}
