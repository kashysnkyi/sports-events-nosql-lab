# NoSQL у системі спортивних подій

Лабораторна робота демонструє гібридне зберігання даних для каталогу спортивних подій:

- PostgreSQL - нормалізоване джерело даних;
- MongoDB - денормалізована read-модель каталогу;
- Redis - кеш, лічильники та рейтинг популярності.

## Швидкий запуск

Потрібні Docker Desktop і .NET 8 SDK.

```powershell
docker compose up -d
dotnet run --project src/SportsEvents.NoSqlLab -- nosql-sync
dotnet run --project src/SportsEvents.NoSqlLab -- nosql-search "Київ" 20
dotnet run --project src/SportsEvents.NoSqlLab -- redis-demo
```

Для відтворення тесту швидкодії:

```powershell
Get-Content postgres/benchmark-seed.sql | docker compose exec -T postgres psql -U postgres -d sports_events
dotnet run --project src/SportsEvents.NoSqlLab -- nosql-sync
dotnet run --project src/SportsEvents.NoSqlLab -- benchmark "Київ" 500
```

Детальний опис методики, аргументація та отримані результати наведені у [REPORT.md](REPORT.md). Сирий результат вимірювання міститься у [benchmark/results.json](benchmark/results.json).

## Звіт

- [PDF-звіт](report/sports-events-nosql-lab-report.pdf)
- [LaTeX-джерело](report/sports-events-nosql-lab-report.tex)
