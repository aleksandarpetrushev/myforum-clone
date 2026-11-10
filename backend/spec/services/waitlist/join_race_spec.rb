require "rails_helper"

# When the insert loses a race (RecordNotUnique), Join reads back the row the other request created and answers for
# what it is. The rescue reads through the event it was given, so the spec stubs that lookup to return the winner;
# a real second connection would deadlock on the event row Join holds locked.
RSpec.describe "a waitlist join that loses a race to create the row" do
  let(:organization) { Organization.create!(name: "Harbor", slug: "harbor-join") }
  let(:event) do
    Event.create!(
      organization: organization, title: "Full", description: "Talk", starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 1.hour, location: "Lisbon", kind: "in_person", capacity: 1, reserved_spots: 1,
      status: "published"
    )
  end
  let(:ana) { User.create!(email: "ana-race@example.com", name: "Ana", password: "password") }

  def lose_race_to(winner)
    allow_any_instance_of(Waitlist::Join).to receive(:join).and_raise(ActiveRecord::RecordNotUnique)
    lookup = instance_double(ActiveRecord::Associations::CollectionProxy)
    allow(lookup).to receive(:find_by!).with(user_id: ana.id).and_return(winner)
    allow(event).to receive(:registrations).and_return(lookup)
  end

  it "reports a registration that won the race as already registered, not as a place in line" do
    lose_race_to(Registration.new(user: ana, event: event, status: "confirmed"))

    expect { Waitlist::Join.new(user: ana, event: event).call }.to raise_error(Waitlist::Join::AlreadyRegistered)
  end

  it "answers a second join that won the race as the same place in line" do
    lose_race_to(Registration.new(user: ana, event: event, status: "waitlisted"))

    result = Waitlist::Join.new(user: ana, event: event).call
    expect(result.created).to be(false)
    expect(result.registration.status).to eq("waitlisted")
  end
end
