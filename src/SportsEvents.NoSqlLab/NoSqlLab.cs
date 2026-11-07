using System.Diagnostics;
using System.Text.Json;
using Dapper;
using MongoDB.Bson;
using MongoDB.Driver;
using Npgsql;
using StackExchange.Redis;

namespace SportsEvents.NoSql;

public sealed record NoSqlSettings(string MongoUrl, string MongoDatabase, string RedisUrl)
{
    public static NoSqlSettings FromEnvironment() => new(
        Environment.GetEnvironmentVariable("MONGO_URL") ?? "mongodb://127.0.0.1:27017",
        Environment.GetEnvironmentVariable("MONGO_DB") ?? "sports_events_nosql",
        Environment.GetEnvironmentVariable("REDIS_URL") ?? "127.0.0.1:6379");
}

internal sealed class SqlCatalogRow
{
    public Guid Id { get; init; }
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public string Status { get; init; } = "";
    public DateTimeOffset StartsAt { get; init; }
    public DateTimeOffset EndsAt { get; init; }
    public DateTimeOffset? RegistrationDeadline { get; init; }
    public int? Capacity { get; init; }
    public DateTimeOffset LastModifiedAt { get; init; }
    public Guid SportId { get; init; }
    public string SportName { get; init; } = "";
    public Guid VenueId { get; init; }
    public string VenueName { get; init; } = "";
    public string VenueAddress { get; init; } = "";
    public string VenueCity { get; init; } = "";
    public Guid OrganizerId { get; init; }
    public string OrganizerName { get; init; } = "";
    public string CategoriesJson { get; init; } = "[]";
    public long ConfirmedRegistrations { get; init; }
}

public sealed class EventCatalogMongoStore
{
    private readonly IMongoCollection<BsonDocument> _collection;

    public EventCatalogMongoStore(NoSqlSettings settings)
    {
        var client = new MongoClient(settings.MongoUrl);
        _collection = client.GetDatabase(settings.MongoDatabase)
            .GetCollection<BsonDocument>("event_catalog");
    }

    public async Task EnsureIndexesAsync(CancellationToken ct)
    {
        var keys = Builders<BsonDocument>.IndexKeys;
        var models = new[]
        {
            new CreateIndexModel<BsonDocument>(
                keys.Ascending("status").Ascending("venue.city").Ascending("startsAt").Ascending("_id"),
                new CreateIndexOptions { Name = "ix_catalog_status_city_start" }),
            new CreateIndexModel<BsonDocument>(
                keys.Text("name").Text("sport.name").Text("categories.name"),
                new CreateIndexOptions { Name = "ix_catalog_full_text", DefaultLanguage = "none" }),
            new CreateIndexModel<BsonDocument>(
                keys.Descending("lastModifiedAt"),
                new CreateIndexOptions { Name = "ix_catalog_last_modified" })
        };
        await _collection.Indexes.CreateManyAsync(models, ct);
    }

    public async Task<int> ReplaceFromPostgresAsync(string postgresConnectionString, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(postgresConnectionString);
        var rows = (await connection.QueryAsync<SqlCatalogRow>(new CommandDefinition(
            """
            select id,name,description,status,starts_at,ends_at,registration_deadline,capacity,last_modified_at,
                   sport_id,sport_name,venue_id,venue_name,venue_address,venue_city,
                   organizer_id,organizer_name,categories::text as categories_json,confirmed_registrations
            from sports.v_event_catalog_sql
            order by id
            """, cancellationToken: ct))).AsList();

        var writes = rows.Select(row => new ReplaceOneModel<BsonDocument>(
            Builders<BsonDocument>.Filter.Eq("_id", row.Id.ToString()), ToDocument(row))
        {
            IsUpsert = true
        }).Cast<WriteModel<BsonDocument>>().ToList();

        await _collection.DeleteManyAsync(Builders<BsonDocument>.Filter.Empty, ct);
        if (writes.Count > 0)
            await _collection.BulkWriteAsync(writes, new BulkWriteOptions { IsOrdered = false }, ct);
        await EnsureIndexesAsync(ct);
        return rows.Count;
    }

    public Task<List<BsonDocument>> SearchAsync(
        string city, DateTimeOffset from, DateTimeOffset to, int limit, CancellationToken ct)
    {
        var filter = Builders<BsonDocument>.Filter.Eq("status", "published")
            & Builders<BsonDocument>.Filter.Eq("venue.city", city)
            & Builders<BsonDocument>.Filter.Gte("startsAt", from.UtcDateTime)
            & Builders<BsonDocument>.Filter.Lt("startsAt", to.UtcDateTime);

        return _collection.Find(filter)
            .Sort(Builders<BsonDocument>.Sort.Ascending("startsAt").Ascending("_id"))
            .Limit(Math.Clamp(limit, 1, 500))
            .ToListAsync(ct);
    }

    private static BsonDocument ToDocument(SqlCatalogRow row)
    {
        var categories = BsonDocument.Parse("{\"items\":" + row.CategoriesJson + "}")
            ["items"].AsBsonArray;
        return new BsonDocument
        {
            ["_id"] = row.Id.ToString(),
            ["name"] = row.Name,
            ["description"] = row.Description is null ? BsonNull.Value : row.Description,
            ["status"] = row.Status,
            ["startsAt"] = row.StartsAt.UtcDateTime,
            ["endsAt"] = row.EndsAt.UtcDateTime,
            ["registrationDeadline"] = row.RegistrationDeadline is null
                ? BsonNull.Value : row.RegistrationDeadline.Value.UtcDateTime,
            ["capacity"] = row.Capacity is null ? BsonNull.Value : row.Capacity.Value,
            ["sport"] = new BsonDocument { ["id"] = row.SportId.ToString(), ["name"] = row.SportName },
            ["venue"] = new BsonDocument
            {
                ["id"] = row.VenueId.ToString(),
                ["name"] = row.VenueName,
                ["address"] = row.VenueAddress,
                ["city"] = row.VenueCity
            },
            ["organizer"] = new BsonDocument
            {
                ["id"] = row.OrganizerId.ToString(),
                ["name"] = row.OrganizerName
            },
            ["categories"] = categories,
            ["confirmedRegistrations"] = row.ConfirmedRegistrations,
            ["lastModifiedAt"] = row.LastModifiedAt.UtcDateTime
        };
    }
}

public sealed record LatencySummary(double MeanMs, double MedianMs, double P95Ms, double MinMs, double MaxMs);
public sealed record BenchmarkSide(string Database, int ResultCount, LatencySummary Latency);
public sealed record BenchmarkReport(
    string Scenario, string City, DateTimeOffset From, DateTimeOffset To,
    int Iterations, int WarmupIterations, BenchmarkSide PostgreSql, BenchmarkSide MongoDb,
    double MeanSpeedup, DateTimeOffset MeasuredAt);

public static class CatalogBenchmark
{
    public static async Task<BenchmarkReport> RunAsync(
        string postgresConnectionString,
        EventCatalogMongoStore mongo,
        string city,
        DateTimeOffset from,
        DateTimeOffset to,
        int limit,
        int iterations,
        CancellationToken ct)
    {
        const int warmups = 8;
        iterations = Math.Clamp(iterations, 10, 5000);
        await using var postgres = new NpgsqlConnection(postgresConnectionString);
        await postgres.OpenAsync(ct);

        for (var i = 0; i < warmups; i++)
        {
            await QueryPostgresAsync(postgres, city, from, to, limit, ct);
            await mongo.SearchAsync(city, from, to, limit, ct);
        }

        var sqlTimes = new long[iterations];
        var mongoTimes = new long[iterations];
        var sqlCount = 0;
        var mongoCount = 0;

        for (var i = 0; i < iterations; i++)
        {
            IReadOnlyList<SqlCatalogRow> sqlRows;
            List<BsonDocument> mongoRows;
            if (i % 2 == 0)
            {
                var started = Stopwatch.GetTimestamp();
                sqlRows = await QueryPostgresAsync(postgres, city, from, to, limit, ct);
                sqlTimes[i] = Stopwatch.GetTimestamp() - started;

                started = Stopwatch.GetTimestamp();
                mongoRows = await mongo.SearchAsync(city, from, to, limit, ct);
                mongoTimes[i] = Stopwatch.GetTimestamp() - started;
            }
            else
            {
                var started = Stopwatch.GetTimestamp();
                mongoRows = await mongo.SearchAsync(city, from, to, limit, ct);
                mongoTimes[i] = Stopwatch.GetTimestamp() - started;

                started = Stopwatch.GetTimestamp();
                sqlRows = await QueryPostgresAsync(postgres, city, from, to, limit, ct);
                sqlTimes[i] = Stopwatch.GetTimestamp() - started;
            }

            sqlCount = sqlRows.Count;
            mongoCount = mongoRows.Count;
            if (sqlCount != mongoCount)
                throw new InvalidOperationException(
                    $"The stores returned different result counts: PostgreSQL={sqlCount}, MongoDB={mongoCount}. Run nosql-sync again.");
            var sqlIds = sqlRows.Select(row => row.Id.ToString()).OrderBy(id => id, StringComparer.Ordinal);
            var mongoIds = mongoRows.Select(row => row["_id"].AsString).OrderBy(id => id, StringComparer.Ordinal);
            if (!sqlIds.SequenceEqual(mongoIds, StringComparer.Ordinal))
                throw new InvalidOperationException("PostgreSQL and MongoDB returned different event identifiers.");
        }

        var sqlLatency = Summarize(sqlTimes);
        var mongoLatency = Summarize(mongoTimes);
        return new BenchmarkReport(
            "Published event cards filtered by city and date range, ordered by start time",
            city, from, to, iterations, warmups,
            new BenchmarkSide("PostgreSQL view over 6 normalized tables", sqlCount, sqlLatency),
            new BenchmarkSide("MongoDB denormalized event_catalog", mongoCount, mongoLatency),
            mongoLatency.MeanMs == 0 ? 0 : sqlLatency.MeanMs / mongoLatency.MeanMs,
            DateTimeOffset.UtcNow);
    }

    public static string ToJson(BenchmarkReport report) =>
        JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });

    private static async Task<IReadOnlyList<SqlCatalogRow>> QueryPostgresAsync(
        NpgsqlConnection connection, string city, DateTimeOffset from,
        DateTimeOffset to, int limit, CancellationToken ct)
    {
        var rows = await connection.QueryAsync<SqlCatalogRow>(new CommandDefinition(
            """
            select id,name,description,status,starts_at,ends_at,registration_deadline,capacity,last_modified_at,
                   sport_id,sport_name,venue_id,venue_name,venue_address,venue_city,
                   organizer_id,organizer_name,categories::text as categories_json,confirmed_registrations
            from sports.fn_search_event_catalog(@city,@from_at,@to_at,@row_limit)
            """,
            new { city, from_at = from, to_at = to, row_limit = limit },
            cancellationToken: ct));
        return rows.AsList();
    }

    private static LatencySummary Summarize(long[] ticks)
    {
        var values = ticks.Select(value => value * 1000.0 / Stopwatch.Frequency)
            .OrderBy(value => value).ToArray();
        return new LatencySummary(
            values.Average(), Percentile(values, 0.50), Percentile(values, 0.95), values[0], values[^1]);
    }

    private static double Percentile(double[] sorted, double percentile)
    {
        var index = Math.Clamp((int)Math.Ceiling(percentile * sorted.Length) - 1, 0, sorted.Length - 1);
        return sorted[index];
    }
}

public static class RedisLabDemo
{
    public static async Task RunAsync(string redisUrl)
    {
        await using var connection = await ConnectionMultiplexer.ConnectAsync(redisUrl);
        var db = connection.GetDatabase();
        var eventId = "00000000-0000-0000-0000-000000000301";

        var card = JsonSerializer.Serialize(new
        {
            id = eventId,
            name = "Київський марафон",
            city = "Київ",
            startsAt = "2027-04-18T09:00:00+03:00"
        });
        await db.StringSetAsync($"event:{eventId}:card", card, TimeSpan.FromMinutes(10));
        await db.HashSetAsync($"event:{eventId}:counters", new HashEntry[]
        {
            new("views", 1250),
            new("registrations", 184)
        });
        await db.SetAddAsync("events:city:Київ", eventId);
        await db.SortedSetIncrementAsync("events:popular", eventId, 1250);
        await db.SortedSetIncrementAsync("events:popular", "00000000-0000-0000-0000-000000000302", 970);

        Console.WriteLine($"GET event card: {await db.StringGetAsync($"event:{eventId}:card")}");
        Console.WriteLine($"TTL: {await db.KeyTimeToLiveAsync($"event:{eventId}:card")}");
        Console.WriteLine("HGETALL counters:");
        foreach (var item in await db.HashGetAllAsync($"event:{eventId}:counters"))
            Console.WriteLine($"  {item.Name}: {item.Value}");
        Console.WriteLine($"SMEMBERS city: {string.Join(", ", await db.SetMembersAsync("events:city:Київ"))}");
        Console.WriteLine("ZREVRANGE popular:");
        foreach (var item in await db.SortedSetRangeByRankWithScoresAsync("events:popular", 0, 4, Order.Descending))
            Console.WriteLine($"  {item.Element}: {item.Score}");
    }
}
