require "rails_helper"

RSpec.describe "discovery benchmark", type: :request do
  it "loads a tiny dataset and times the events endpoint" do
    manifest = Bench::Dataset.generate!(scale: :tiny)
    config = Bench::Dataset::SCALES.fetch(:tiny)

    expect(manifest.dig("counts", "events")).to eq(config.fetch(:events))
    expect(manifest.dig("counts", "users")).to eq(config.fetch(:users))
    expect(manifest.dig("counts", "organizations")).to eq(config.fetch(:organizations))
    expect(manifest.dig("counts", "memberships")).to eq(config.fetch(:memberships))
    expect(Event.where("title ILIKE ?", "%#{Bench::Dataset::SELECTIVE_TOKEN}%").count).to be_positive

    report = Bench::Discovery.run!(manifest: manifest, iterations: 2, warmup: 1, mix: 8, explain: true)

    expect(report["checks_passed"]).to be(true), report.dig("checks", "failures").inspect
    selective = report["scenarios"].find { |scenario| scenario["name"] == "keyword_selective" }
    expect(selective["samples"]).to eq(2)
    expect(selective["p95_ms"]).to be > 0
    expect(selective["rows"]).to be <= 20
    expect(selective["explain"]).to include("execution_ms")
    expect(report.dig("mix", "samples")).to eq(8)
    expect(report.dig("checks", "pagination")).to include("page_1_and_2_overlap")
  end

  it "builds the mix offered at 300 requests per second" do
    manifest = Bench::Dataset.generate!(scale: :tiny)
    templates = Bench::Traffic.templates(manifest)
    planned = Bench::Traffic.schedule(templates, 1_000, Random.new(42))
    counts = planned.group_by { |item| item.fetch("scenario") }.transform_values(&:size)

    expect(templates["upcoming_page_1"].fetch("path")).to eq("/api/events")
    expect(templates["keyword_selective"].fetch("path")).to include(Bench::Dataset::SELECTIVE_TOKEN)
    expect(counts["upcoming_page_1"]).to be_between(300, 500)
    expect(counts["keyword_selective"]).to be_between(30, 120)
    expect(planned.sum { |item| item.fetch("path").start_with?("/api/events") ? 1 : 0 }).to eq(1_000)
  end

  it "counts only completions inside the measurement window" do
    samples = [
      { "scheduled" => 101, "started_at" => 101.1, "finished_at" => 101.2, "status" => 200, "at_deadline" => "completed", "service_ms" => 10, "e2e_ms" => 20, "scenario" => "upcoming_page_1" },
      { "scheduled" => 102, "started_at" => 119.0, "finished_at" => 121.0, "status" => 200, "at_deadline" => "in_flight", "service_ms" => 2000, "e2e_ms" => 19_000, "scenario" => "keyword_selective" },
      { "scheduled" => 103, "started_at" => 120.5, "finished_at" => 120.6, "status" => 200, "at_deadline" => "queued", "service_ms" => 100, "e2e_ms" => 17_600, "scenario" => "keyword_common" },
      { "scheduled" => 104, "at_deadline" => "queued", "unserved" => true, "scenario" => "location" },
      { "scheduled" => 50, "started_at" => 50, "finished_at" => 50.1, "status" => 200, "at_deadline" => "completed", "service_ms" => 5, "e2e_ms" => 5, "scenario" => "upcoming_page_1" }
    ]

    summary = Bench::Traffic.summarize(samples, duration: 20, warmup: 5, measure_at: 100)

    expect(summary["offered"]).to eq(4)
    expect(summary["completed_in_window"]).to eq(1)
    expect(summary["completed_rps"]).to eq(0.05)
    expect(summary["completed_during_drain"]).to eq(2)
    expect(summary.dig("at_deadline", "queued")).to eq(2)
    expect(summary.dig("at_deadline", "in_flight")).to eq(1)
    expect(summary["abandoned"]).to eq(1)
    expect(summary.dig("service_ms", "p50")).to eq(10.0)
    expect(summary["scenarios"].find { |scenario| scenario["name"] == "upcoming_page_1" }["samples"]).to eq(1)
  end
end
