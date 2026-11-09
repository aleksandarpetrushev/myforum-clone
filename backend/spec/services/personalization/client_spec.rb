require "rails_helper"

RSpec.describe Personalization::Client do
  it "turns a refused connection into Unavailable" do
    allow(Personalization::Http).to receive(:base_url).and_return("http://127.0.0.1:1")

    expect { described_class.recommended_event_ids(user_id: 1, limit: 20) }
      .to raise_error(Personalization::Unavailable)
  end

  it "turns a non-2xx answer into Unavailable, and reads event ids from a 200" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    body = { data: [{ event_id: 7 }, { event_id: 3 }] }.to_json
    answers = ["HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"]
    thread = Thread.new do
      answers.each do |answer|
        socket = server.accept
        socket.gets("\r\n\r\n")
        socket.write(answer)
        socket.close
      end
    end
    allow(Personalization::Http).to receive(:base_url).and_return("http://127.0.0.1:#{port}")

    expect { described_class.recommended_event_ids(user_id: 1, limit: 20) }.to raise_error(Personalization::Unavailable, /500/)
    expect(described_class.recommended_event_ids(user_id: 1, limit: 20)).to eq([7, 3])
  ensure
    thread&.join(2)
    server&.close
  end
end
