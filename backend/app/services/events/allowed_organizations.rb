module Events
  # The rules for an event's allowed organizations, shared by Events::Create and Events::Update.
  module AllowedOrganizations
    # Checked before any write so bad ids return 422 instead of reaching the foreign key.
    def self.validate(event, organization_ids, visibility:)
      if visibility == "organization_restricted" && organization_ids.empty?
        event.errors.add(:allowed_organization_ids, :blank)
      end
      return if Organization.where(id: organization_ids).count == organization_ids.size

      event.errors.add(:allowed_organization_ids, :invalid)
    end

    def self.replace(event, organization_ids)
      event.event_allowed_organizations.destroy_all
      organization_ids.each do |organization_id|
        event.event_allowed_organizations.create!(organization_id: organization_id)
      end
    end
  end
end
