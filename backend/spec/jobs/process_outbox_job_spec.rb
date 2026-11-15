require "rails_helper"

# MF-302: the poller goes again at once while it is working through a backlog, and never spins on rows it cannot send.
RSpec.describe ProcessOutboxJob do
  describe ".wait_after" do
    it "goes again at once after publishing a full batch" do
      expect(described_class.wait_after(published: 500, full_batch: true)).to be_nil
    end

    it "waits a second after a partial batch" do
      expect(described_class.wait_after(published: 3, full_batch: false)).to eq(1.second)
    end

    it "waits five seconds when nothing was published, even if the batch was full of rows waiting behind failures" do
      expect(described_class.wait_after(published: 0, full_batch: true)).to eq(5.seconds)
      expect(described_class.wait_after(published: 0, full_batch: false)).to eq(5.seconds)
    end
  end
end
