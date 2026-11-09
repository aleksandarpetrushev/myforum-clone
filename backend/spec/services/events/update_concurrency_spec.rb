require "rails_helper"

RSpec.describe "saving one event concurrently" do
  self.use_transactional_tests = false

  after do
    OutboxEvent.delete_all
    Event.delete_all
    Organization.delete_all
  end

  let(:event) do
    Event.create!(
      organization: Organization.create!(name: "Harbor", slug: "harbor-save"),
      title: "Original",
      description: "Session",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour,
      location: "Lisbon",
      kind: "in_person",
      capacity: 10,
      status: "published"
    )
  end

  def save_at_once(*attribute_sets)
    gate = Queue.new
    threads = attribute_sets.map do |attributes|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection do
          Events::Update.new(event: Event.find(event.id), attributes: attributes).call
          :saved
        end
      end
    end
    attribute_sets.size.times { gate << :go }
    threads.map(&:value)
  end

  def updated_rows
    OutboxEvent.where(event_type: "EventUpdated", aggregate_id: event.id)
  end

  it "keeps both changes when two saves change different fields at the same moment" do
    results = save_at_once({ "title" => "New title" }, { "location" => "Davos" })

    expect(results).to eq(%i[saved saved])
    expect(event.reload).to have_attributes(title: "New title", location: "Davos", revision: 2)
    expect(updated_rows.pluck(:idempotency_key)).to contain_exactly("event_updated:#{event.id}:1", "event_updated:#{event.id}:2")
  end

  it "accepts both when two saves change the same field, and keeps one of the values" do
    results = save_at_once({ "title" => "From Ana" }, { "title" => "From Ben" })

    expect(results).to eq(%i[saved saved])
    expect(event.reload.title).to be_in(["From Ana", "From Ben"])
    expect(event.revision).to eq(2)
    expect(updated_rows.count).to eq(2)
    # The row with the higher revision carries the title that was saved last.
    expect(updated_rows.max_by { |row| row.payload.dig("event", "revision") }.payload.dig("event", "title")).to eq(event.title)
  end
end
