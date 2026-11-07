using Dapper;
using MongoDB.Bson;
using SportsEvents.NoSql;

DefaultTypeMap.MatchNamesWithUnderscores = true;

var command = args.FirstOrDefault()?.ToLowerInvariant() ?? "help";
var postgres = Environment.GetEnvironmentVariable("SPORTS_DB")
    ?? "Host=127.0.0.1;Port=5432;Database=sports_events;Username=postgres;Password=postgres";
var settings = NoSqlSettings.FromEnvironment();
var mongo = new EventCatalogMongoStore(settings);

try
{
    switch (command)
    {
        case "nosql-sync":
            var count = await mongo.ReplaceFromPostgresAsync(postgres, CancellationToken.None);
            Console.WriteLine($"Синхронізовано документів: {count}");
            break;

        case "nosql-search":
            var city = args.ElementAtOrDefault(1) ?? "Київ";
            var limit = int.TryParse(args.ElementAtOrDefault(2), out var parsedLimit) ? parsedLimit : 20;
            var documents = await mongo.SearchAsync(
                city,
                new DateTimeOffset(2027, 1, 1, 0, 0, 0, TimeSpan.Zero),
                new DateTimeOffset(2028, 1, 1, 0, 0, 0, TimeSpan.Zero),
                limit,
                CancellationToken.None);
            foreach (var document in documents)
                Console.WriteLine(document.ToJson(new MongoDB.Bson.IO.JsonWriterSettings { Indent = true }));
            Console.WriteLine($"Знайдено: {documents.Count}");
            break;

        case "benchmark":
            var benchmarkCity = args.ElementAtOrDefault(1) ?? "Київ";
            var iterations = int.TryParse(args.ElementAtOrDefault(2), out var parsedIterations)
                ? parsedIterations : 500;
            var report = await CatalogBenchmark.RunAsync(
                postgres,
                mongo,
                benchmarkCity,
                new DateTimeOffset(2027, 1, 1, 0, 0, 0, TimeSpan.Zero),
                new DateTimeOffset(2028, 1, 1, 0, 0, 0, TimeSpan.Zero),
                50,
                iterations,
                CancellationToken.None);
            Console.WriteLine(CatalogBenchmark.ToJson(report));
            break;

        case "redis-demo":
            await RedisLabDemo.RunAsync(settings.RedisUrl);
            break;

        default:
            Console.WriteLine("Команди:");
            Console.WriteLine("  nosql-sync");
            Console.WriteLine("  nosql-search [місто] [кількість]");
            Console.WriteLine("  benchmark [місто] [ітерації]");
            Console.WriteLine("  redis-demo");
            break;
    }
}
catch (Exception exception)
{
    Console.Error.WriteLine(exception.Message);
    Environment.ExitCode = 1;
}
