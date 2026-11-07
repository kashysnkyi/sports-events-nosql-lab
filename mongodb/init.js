db = db.getSiblingDB("sports_events_nosql");

db.createCollection("event_catalog", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "name", "status", "startsAt", "sport", "venue", "categories"],
      properties: {
        _id: { bsonType: "string" },
        name: { bsonType: "string" },
        status: { enum: ["draft", "published", "cancelled", "completed"] },
        startsAt: { bsonType: "date" },
        endsAt: { bsonType: "date" },
        sport: {
          bsonType: "object",
          required: ["id", "name"]
        },
        venue: {
          bsonType: "object",
          required: ["id", "name", "city"]
        },
        categories: { bsonType: "array" },
        confirmedRegistrations: { bsonType: ["long", "int"] }
      }
    }
  }
});

db.event_catalog.createIndex(
  { status: 1, "venue.city": 1, startsAt: 1, _id: 1 },
  { name: "ix_catalog_status_city_start" }
);

db.event_catalog.createIndex(
  { name: "text", "sport.name": "text", "categories.name": "text" },
  { name: "ix_catalog_full_text", default_language: "none" }
);

db.event_catalog.createIndex(
  { lastModifiedAt: -1 },
  { name: "ix_catalog_last_modified" }
);
