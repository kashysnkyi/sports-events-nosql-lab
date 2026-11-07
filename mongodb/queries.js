db = db.getSiblingDB("sports_events_nosql");

db.event_catalog.find(
  {
    status: "published",
    "venue.city": "Київ",
    startsAt: {
      $gte: ISODate("2027-01-01T00:00:00Z"),
      $lt: ISODate("2028-01-01T00:00:00Z")
    }
  },
  { name: 1, startsAt: 1, "sport.name": 1, "venue.name": 1, confirmedRegistrations: 1 }
).sort({ startsAt: 1, _id: 1 }).limit(20);

db.event_catalog.find(
  { $text: { $search: "марафон біг" } },
  { name: 1, "sport.name": 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } }).limit(10);

db.event_catalog.aggregate([
  { $match: { status: "published" } },
  {
    $group: {
      _id: "$venue.city",
      events: { $sum: 1 },
      registrations: { $sum: "$confirmedRegistrations" }
    }
  },
  { $sort: { events: -1 } },
  { $limit: 10 }
]);

db.event_catalog.find({
  status: "published",
  "venue.city": "Київ",
  startsAt: { $gte: ISODate("2027-01-01T00:00:00Z"), $lt: ISODate("2028-01-01T00:00:00Z") }
}).sort({ startsAt: 1, _id: 1 }).limit(50).explain("executionStats");
