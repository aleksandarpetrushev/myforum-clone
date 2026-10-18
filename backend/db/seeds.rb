# Development seed data. Re-running deletes forum rows first.
raise "Refusing to seed outside development" unless Rails.env.development?

AnalyticsEvent.delete_all
Notification.delete_all
OutboxEvent.delete_all
Registration.delete_all
EventSpeaker.delete_all
EventTopic.delete_all
TopicFollow.delete_all
OrganizationMembership.delete_all
Event.delete_all
Speaker.delete_all
Topic.delete_all
Organization.delete_all
User.delete_all

PASSWORD = "password"
CITIES = ["Berlin", "London", "New York", "Lisbon", "Toronto"].freeze

organizations = [
  ["Northwind Collective", "northwind"],
  ["Harbor Institute", "harbor"],
  ["Lumen Labs", "lumen"],
  ["Fieldnote", "fieldnote"],
  ["Atlas Guild", "atlas"],
  ["Kindred", "kindred"],
  ["Open Circuit", "open-circuit"],
  ["Civic Hall", "civic-hall"]
].map { |name, slug| Organization.create!(name: name, slug: slug) }

topic_names = [
  "Climate", "Public health", "AI policy", "Cities", "Education",
  "Energy", "Labor", "Democracy", "Food systems", "Mobility",
  "Housing", "Science", "Design", "Security", "Economy"
]
topics = topic_names.map { |name|
  Topic.create!(name: name, slug: name.downcase.gsub(" ", "-"))
}

speakers = [
  ["Amina Shah", "Urban researcher"],
  ["Luis Ortega", "Energy analyst"],
  ["Nora Berg", "Public health lead"],
  ["Jonah Ellis", "Policy editor"],
  ["Priya Raman", "Product strategist"],
  ["Elena Voss", "Climate scientist"],
  ["Marcus Hale", "Labor economist"],
  ["Sofia Mendes", "Civic designer"],
  ["Kenji Sato", "Security engineer"],
  ["Hannah Cole", "Education director"],
  ["Omar Farouk", "Food systems fellow"],
  ["Greta Lind", "Mobility planner"]
].map { |name, title| Speaker.create!(name: name, title: title) }

users = []
users << User.create!(email: "alex@example.com", name: "Alex Morgan", password: PASSWORD, location: "Berlin")
29.times do |index|
  number = index + 2
  users << User.create!(
    email: format("member%02d@example.com", number),
    name: "Member #{number}",
    password: PASSWORD,
    location: CITIES[index % CITIES.length]
  )
end

users.each_with_index do |user, user_index|
  primary = organizations[user_index % organizations.length]
  secondary = organizations[(user_index + 3) % organizations.length]
  OrganizationMembership.create!(
    user: user,
    organization: primary,
    role: user_index < 8 ? "admin" : "member"
  )
  next if secondary == primary

  OrganizationMembership.create!(user: user, organization: secondary, role: "member")
end

users.each_with_index do |user, index|
  topics.rotate(index).first(3).each do |topic|
    TopicFollow.create!(user: user, topic: topic)
  end
end

100.times do |index|
  organization = organizations[index % organizations.length]
  start_time = (index < 80 ? index.days.from_now.change(hour: 9) : (index - 79).days.ago.change(hour: 9))
  capacity = [20, 40, 80, 120][index % 4]
  event = Event.create!(
    organization: organization,
    title: "Forum session #{index + 1}: #{topics[index % topics.length].name}",
    description: "A working session on #{topics[index % topics.length].name.downcase} for practitioners. Session #{index + 1} covers what teams can change without rebuilding their programs.",
    starts_at: start_time,
    ends_at: start_time + 2.hours,
    location: index % 5 == 0 ? "Online" : CITIES[index % CITIES.length],
    kind: index % 5 == 0 ? "online" : "in_person",
    capacity: capacity,
    reserved_spots: 0,
    status: "published"
  )
  event.topics << topics[index % topics.length]
  event.topics << topics[(index + 3) % topics.length]
  event.speakers << speakers[index % speakers.length]

  next unless index < 70 && index % 3 != 2

  attendee_count = if index % 11 == 0
    [capacity - 1, users.length].min
  elsif index % 7 == 0
    [25, capacity, users.length].min
  else
    (index % 5) + 1
  end

  attendees = users.first(attendee_count)
  attendees.each do |user|
    Registration.create!(user: user, event: event, status: "confirmed")
  end
  event.update!(reserved_spots: attendees.length)
end

Event.find_each do |event|
  OutboxEvent.record!(
    event_type: "EventUpdated",
    aggregate_type: "Event",
    aggregate_id: event.id,
    idempotency_key: "seed:event:#{event.id}",
    payload: { "event" => event.snapshot }
  )
end

TopicFollow.find_each do |follow|
  OutboxEvent.record!(
    event_type: "TopicFollowed",
    aggregate_type: "TopicFollow",
    aggregate_id: follow.id,
    idempotency_key: "seed:topic_followed:#{follow.user_id}:#{follow.topic_id}",
    payload: {
      "user_id" => follow.user_id,
      "topic_id" => follow.topic_id,
      "user_location" => follow.user.location
    }
  )
end

alex = users.first
Notification.create!(
  user: alex,
  kind: "registration_confirmed",
  title: "Registration confirmed",
  body: "You are registered for an upcoming forum session.",
  idempotency_key: "seed:notification:alex"
)
