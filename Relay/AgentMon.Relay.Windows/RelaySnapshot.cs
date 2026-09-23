using System.Text.Json;
using System.Text.Json.Serialization;

namespace AgentMon.Relay.Windows;

internal sealed record RelayHost(string Id, string Name, string Platform = "windows");

internal sealed record RelaySession(
    string Id, string Project, string Task, string? Repository, string? Branch,
    string Activity, DateTimeOffset UpdatedAt);

internal sealed record RelaySnapshot(
    int ProtocolVersion, string RelayVersion, DateTimeOffset GeneratedAt,
    RelayHost Host, IReadOnlyList<RelaySession> Sessions)
{
    internal const int Version = 1;
    internal const int Port = 47831;
    internal const string ApplicationVersion = "0.1.0";

    internal static readonly JsonSerializerOptions JsonOptions = CreateJsonOptions();

    private static JsonSerializerOptions CreateJsonOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        options.Converters.Add(new UtcDateConverter());
        return options;
    }

    private sealed class UtcDateConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
            => reader.GetDateTimeOffset().ToUniversalTime();

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
            => writer.WriteStringValue(value.UtcDateTime.ToString("O", System.Globalization.CultureInfo.InvariantCulture));
    }
}
