// SPDX-License-Identifier: MIT
using System.Globalization;
using System.Text.Json;

namespace CTC.Core;

public static class Json
{
    public static JsonElement At(this JsonElement e, string key) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) ? v : default;
    public static string Text(this JsonElement e) => e.ValueKind == JsonValueKind.String ? e.GetString() ?? "" : "";
    public static string Text(this JsonElement e, string key) => e.At(key).Text();
    public static long? Count(this JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var n) && n >= 0 ? n : null;
    public static long? Count(this JsonElement e, string key) => e.At(key).Count();
    public static double? Number(this JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetDouble(out var n) && double.IsFinite(n) ? n : null;
    public static bool Has(this JsonElement e, string key) => e.At(key).ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null);
    public static IEnumerable<JsonElement> Items(this JsonElement e) => e.ValueKind == JsonValueKind.Array ? e.EnumerateArray() : [];
    public static DateTimeOffset Time(this JsonElement e) =>
        DateTimeOffset.TryParse(e.Text(), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t) ? t : DateTimeOffset.MinValue;
}

public sealed record Usage(long? Input, long? Cached, long? Output, long? Reasoning, long? RecordedTotal = null)
{
    public static Usage Empty { get; } = new(null, null, null, null);
    public long? Total => Input.HasValue && Output.HasValue ? Sum(Input.Value, Output.Value) : RecordedTotal;
    public long? Uncached => Input.HasValue && Cached.HasValue && Cached <= Input ? Input - Cached : null;
    public long? OtherOutput => Output.HasValue && Reasoning.HasValue && Reasoning <= Output ? Output - Reasoning : null;
    public double? CacheRate => Input > 0 && Cached >= 0 && Cached <= Input ? 100d * Cached / Input : null;
    public double? ReasoningRate => Output > 0 && Reasoning >= 0 && Reasoning <= Output ? 100d * Reasoning / Output : null;
    public static Usage Parse(JsonElement e) => new(e.Count("input_tokens"), e.Count("cached_input_tokens"), e.Count("output_tokens"), e.Count("reasoning_output_tokens"), e.Count("total_tokens"));
    public static long? Sum(long a, long b) => a <= long.MaxValue - b ? a + b : null;
}
public sealed record TokenEvent(string Id, DateTimeOffset At, string Model, string Tier, long? Input, long? Cached, long? Output, long? RequestInput, long? Total);
public sealed record ToolResult(string Status, double? Seconds, long? ExitCode, string Session);
public sealed class ToolCall
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public DateTimeOffset At { get; init; }
    public List<string> CommandTypes { get; } = [];
    public Dictionary<string, int> ScriptReferences { get; } = new(StringComparer.Ordinal);
    public List<ToolResult> ShellResults { get; } = [];
    public ToolResult? Result { get; set; }
}
public sealed record ActivityDetail(string Name, long Count, long WithResult, long NoResult, long Success, long Failure, long Unknown, double Seconds);
public sealed record ToolActivity(long Calls, bool Partial, ActivityDetail[] Tools, ActivityDetail[] Exec, KeyValuePair<string,long>[] CommandTypes, KeyValuePair<string,long>[] References, ActivityDetail[] ShellResults);
public sealed record ChatView(string Id, string Title, string Initial, string Model, string Cwd, bool Active, bool LifecycleKnown, bool Subagent,
    string Status, long? Window, Usage Latest, Usage Total, DateTimeOffset UsageAt, DateTimeOffset LastEvent, int Compactions,
    DateTimeOffset LastCompact, ToolActivity Activity, string Error, string Source, long Revision)
{
    public double? ContextPercent => Window > 0 && Latest.Input.HasValue ? 100d * Latest.Input / Window : null;
}
public sealed record MonitorSnapshot(DateTimeOffset At, ChatView[] Chats, string[] Projects, TokenEvent[] Events, QuotaSnapshot? RecordedQuota,
    bool DiscoveryComplete, bool LifecycleComplete, string Warning, string CompactionSource)
{
    public ChatView[] ActiveChats => Chats.Where(x => x.Active && !x.Subagent && At-x.LastEvent<TimeSpan.FromMinutes(10)).ToArray();
}
public sealed record QuotaWindow(string Bucket, string Role, int Minutes, double Used, DateTimeOffset? Reset)
{
    public double Remaining => 100 - Used;
    public string Label => Minutes == 300 ? "5h" : Minutes == 10080 ? "7d" : Minutes >= 60 ? $"{Minutes/60d:0.#}h" : $"{Minutes}m";
    public string Key => $"{Bucket}|{Role}|{Minutes}";
}
public sealed record QuotaSnapshot(string AccountKey, string ProfileStamp, string Plan, string Source, DateTimeOffset Observed, QuotaWindow[] Windows);
public sealed record ModelInfo(string Model, long? Window, long? Maximum, double? UsablePercent);
public sealed record LimitValues(long? Window, long? Compact);
public sealed record LimitBaseline(LimitValues Saved, long? Base, string Source, string Model, ModelInfo? Catalog, long? Live, string Version);
public sealed record QueueEntry(string Path, long? Window, long? Compact, DateTimeOffset SavedAt);
public sealed record QueueView(QueueEntry Entry, bool Changed, string Error, string Status, string[] Chats);
public sealed record RestartStatus(string Status, string Message, DateTimeOffset ExpiresAt, DateTimeOffset Updated, int ProcessId = 0);
public static class Format
{
    public static string Tokens(long? n) => n.HasValue ? n.Value.ToString("N0", CultureInfo.CurrentCulture) : "--";
    public static string Short(long? n) => !n.HasValue ? "--" : n >= 1_000_000 ? $"{n/1_000_000d:0.#}M" : n >= 1000 ? $"{n/1000d:0.#}k" : Tokens(n);
    public static string Limit(long? n) => n?.ToString(CultureInfo.InvariantCulture) ?? "default";
    public static string Percent(double? n) => n.HasValue ? $"{n:0.#}%" : "--";
}
