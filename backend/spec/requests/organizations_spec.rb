require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let!(:atlas) { Organization.create!(name: "Atlas", slug: "atlas") }
  let!(:borealis) { Organization.create!(name: "Borealis", slug: "borealis") }
  let!(:cygnus) { Organization.create!(name: "Cygnus", slug: "cygnus") }
  let(:admin) { User.create!(email: "admin@example.com", name: "Admin", password: "password") }
  let(:member) { User.create!(email: "member@example.com", name: "Member", password: "password") }

  before do
    OrganizationMembership.create!(user: admin, organization: borealis, role: "admin")
    OrganizationMembership.create!(user: admin, organization: atlas, role: "member")
    OrganizationMembership.create!(user: member, organization: atlas, role: "member")
  end

  describe "GET /api/me/organizations" do
    it "returns only the organizations the user administers" do
      get "/api/me/organizations", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json_body["data"]).to eq([{ "id" => borealis.id, "name" => "Borealis" }])
    end

    it "returns an empty list for a user with no admin role" do
      get "/api/me/organizations", headers: auth_headers(member)

      expect(response).to have_http_status(:ok)
      expect(json_body["data"]).to eq([])
    end

    it "rejects an unauthenticated user" do
      get "/api/me/organizations"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/organizations" do
    it "lists every organization for an admin" do
      get "/api/organizations", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(json_body["data"].map { |row| row["name"] }).to eq(%w[Atlas Borealis Cygnus])
    end

    it "is forbidden for a user with no admin role" do
      get "/api/organizations", headers: auth_headers(member)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
