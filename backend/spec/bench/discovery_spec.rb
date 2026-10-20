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
end
