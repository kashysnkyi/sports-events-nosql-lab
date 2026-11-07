# Лабораторна робота №2: NoSQL у системі спортивних подій

## 1. Основні види NoSQL баз даних

| Тип | Модель | Типові системи | Доцільне використання |
|---|---|---|---|
| Документні | JSON/BSON-документи | MongoDB, Couchbase | Каталоги, профілі, read-моделі зі змінною структурою |
| Ключ-значення | Ключ і непрозоре значення | Redis, Valkey, Garnet | Кеш, сесії, лічильники, рейтинги, TTL |
| Колонкові | Розріджені широкі рядки | Cassandra, HBase | Великі потоки подій, часові ряди, горизонтальне масштабування |
| Графові | Вершини та ребра | Neo4j, JanusGraph | Соціальні зв'язки, маршрути, рекомендації |

NoSQL не є повною заміною реляційної СУБД. Вибір залежить від структури даних, типу запитів, вимог до узгодженості та масштабування.

## 2. Обґрунтування для предметної області

PostgreSQL залишається джерелом істини: реєстрація спортсмена, контроль місткості категорії, аудит, soft delete та зв'язки потребують транзакцій і зовнішніх ключів. MongoDB використовується як денормалізована read-модель каталогу.

Картка події читається значно частіше, ніж змінюється. У PostgreSQL вона формується з таких таблиць:

1. `sport_event`;
2. `sport`;
3. `venue`;
4. `app_user`;
5. `event_category`;
6. `event_registration`.

У MongoDB ці дані зберігаються одним документом `event_catalog`: вид спорту, місце, організатор і категорії вкладені, а кількість підтверджених реєстрацій попередньо агрегована. Це усуває JOIN та групування у read-heavy сценарії каталогу.

Недолік підходу - eventual consistency. Після зміни PostgreSQL read-модель треба синхронізувати. У роботі реалізовано повне повторюване оновлення командою `nosql-sync`; у production це доцільно замінити outbox/CDC-процесом.

## 3. Реалізація MongoDB

Документ має таку форму:

```json
{
  "_id": "02446d30-6929-0bd0-bf85-183eaeaa49de",
  "name": "Benchmark event 05476",
  "status": "published",
  "startsAt": "2027-01-01T07:00:00Z",
  "sport": { "id": "...", "name": "Біг" },
  "venue": { "id": "...", "name": "...", "address": "...", "city": "Київ" },
  "organizer": { "id": "...", "name": "Олена Мельник" },
  "categories": [
    { "code": "C1", "name": "Benchmark category 1", "confirmedRegistrations": 12 }
  ],
  "confirmedRegistrations": 36,
  "lastModifiedAt": "2026-11-07T09:00:00Z"
}
```

Створено три індекси:

- compound B-tree `{ status, venue.city, startsAt, _id }` для каталогу;
- text index за назвою події, видом спорту та категоріями;
- descending index за `lastModifiedAt` для інкрементальної синхронізації.

Схема валідації та індекси описані у `mongodb/init.js`, приклади `find`, text search, aggregation та `explain` - у `mongodb/queries.js`. Синхронізація й пошук реалізовані у `src/SportsEvents.NoSqlLab/NoSqlLab.cs` через офіційний MongoDB Driver.

## 4. Еквівалент у SQL

Файл `postgres/nosql-equivalent.sql` створює:

- `sports.v_event_catalog_sql` - SQL-представлення тієї самої картки;
- `sports.fn_search_event_catalog(...)` - параметризований пошук;
- B-tree індекс активних локацій за містом;
- частковий B-tree індекс реєстрацій за категорією і статусом.

Категорії формуються як JSONB-масив корельованою агрегацією. Таким чином SQL і MongoDB повертають семантично однакові дані, але SQL збирає їх під час кожного запиту.

## 5. Тестування швидкодії

### Методика

`postgres/benchmark-seed.sql` повторювано створює:

- 10 000 подій;
- 30 000 категорій;
- 360 000 підтверджених реєстрацій.

Після синхронізації в MongoDB було 10 012 документів разом із демонстраційними подіями. Сценарій: знайти опубліковані події Києва за 2027 рік, відсортувати за датою та повернути перші 50 повних карток.

Виконано 8 прогрівальних і 500 вимірюваних ітерацій. Порядок SQL/MongoDB чергувався. Після кожної ітерації перевірялися не лише кількість, а й множина ідентифікаторів. Обидві БД щоразу повертали однакові 50 подій.

Середовище: Windows 11 Pro, Intel Core i5-12500H (12 ядер / 16 потоків), 31,7 ГБ RAM, PostgreSQL 18.6, MongoDB 9.0.4, .NET SDK 10.0.402, застосунок `net8.0`.

### Результати

| СУБД | Mean, мс | Median, мс | P95, мс | Min, мс | Max, мс |
|---|---:|---:|---:|---:|---:|
| PostgreSQL | 33,831 | 39,041 | 50,440 | 14,111 | 60,747 |
| MongoDB | 2,109 | 1,588 | 4,188 | 0,804 | 40,275 |

У цьому конкретному сценарії MongoDB за середнім часом була швидшою у **16,04 раза**. Результат логічний: MongoDB читає готовий документ через compound index, тоді як PostgreSQL формує картку із шести нормалізованих таблиць та виконує вкладені агрегації.

Це не доводить загальну перевагу MongoDB. Для транзакційного запису, контролю місткості, унікальності реєстрацій та аудиту PostgreSQL залишається кращим. MongoDB доцільна саме як окрема read-модель.

Сирий результат збережено у `benchmark/results.json`.

## 6. NoSQL іншого типу: Redis

Другим типом обрано key-value базу Redis-сумісного типу. Реалізовано:

- `SET/GET` картки події з TTL 10 хвилин;
- `HSET/HGETALL` лічильників переглядів і реєстрацій;
- `SADD/SMEMBERS` множини подій міста;
- `ZADD/ZREVRANGE` рейтингу популярності.

Команда `redis-demo` була перевірена на Redis-сумісному сервері Garnet: картка прочиталася, TTL становив приблизно 10 хвилин, hash повернув `views=1250` і `registrations=184`, set містив подію Києва, а sorted set повернув рейтинг 1250 та 970.

Сирі Redis-команди наведено в `redis/queries.txt`, програмна реалізація - у `RedisLabDemo`.

## 7. Запуск

Найпростіший варіант - Docker Compose:

```powershell
docker compose up -d
$env:SPORTS_DB = "Host=127.0.0.1;Port=5432;Database=sports_events;Username=postgres;Password=postgres"
$env:MONGO_URL = "mongodb://127.0.0.1:27017"
$env:MONGO_DB = "sports_events_nosql"
$env:REDIS_URL = "127.0.0.1:6379"
```

Створення великого тестового набору й запуск:

```powershell
Get-Content postgres/benchmark-seed.sql | docker compose exec -T postgres psql -U postgres -d sports_events
dotnet run --project src/SportsEvents.NoSqlLab -- nosql-sync
dotnet run --project src/SportsEvents.NoSqlLab -- nosql-search "Київ" 20
dotnet run --project src/SportsEvents.NoSqlLab -- benchmark "Київ" 500
dotnet run --project src/SportsEvents.NoSqlLab -- redis-demo
```

Для звичайного демо без великого benchmark-набору достатньо пропустити `benchmark-seed.sql`: Docker Compose автоматично застосує `schema.sql`, `seed.sql` і `nosql-equivalent.sql` до нової бази.

## Висновок

Гібридна схема відповідає навантаженню предметної області: PostgreSQL гарантує цілісність операцій, MongoDB прискорює читання каталогу, Redis надає короткоживучий кеш і рейтинги. Винесення даних виправдане лише для окремих read-heavy та ephemeral сценаріїв, а не як безумовна заміна реляційної моделі.
