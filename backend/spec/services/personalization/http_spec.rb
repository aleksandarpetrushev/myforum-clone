require "rails_helper"

RSpec.describe Personalization::Http do
  it "gives up after one read timeout instead of retrying the request" do
    server = TCPServer.new("127.0.0.1", 0)
    connections = Queue.new
    # Accept connections and never answer, the way a hung Go service behaves.
    thread = Thread.new do
      loop do
        connections << server.accept
      end
    rescue IOError
      nil
    end
    allow(described_class).to receive(:base_url).and_return("http://127.0.0.1:#{server.addr[1]}")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { described_class.get("recommendations", query: { user_id: 1 }, open_timeout: 0.25, read_timeout: 0.3) }
      .to raise_error(Net::ReadTimeout)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(connections.size).to eq(1)
    expect(elapsed).to be < 0.6
  ensure
    server&.close
    thread&.join(1)
    connections&.size&.times { connections.pop.close }
  end
end
