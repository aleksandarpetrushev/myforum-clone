module Events
  class Create
    CREATABLE_STATUSES = %w[draft published].freeze

    def initialize(organization:, attributes:)
      @organization = organization
      @attributes = attributes.to_h.stringify_keys
    end

    def call
      allowed_ids = id_list(@attributes.delete("allowed_organization_ids"))
      topic_ids = id_list(@attributes.delete("topic_ids"))
      @attributes["status"] = "draft" if @attributes["status"].blank?

      event = @organization.events.build(@attributes)
      allowed_ids = [] unless event.visibility == "organization_restricted"
      validate!(event, allowed_ids, topic_ids)

      ApplicationRecord.transaction do
        event.save!
        Events::AllowedOrganizations.replace(event, allowed_ids)
        topic_ids.each { |topic_id| event.event_topics.create!(topic_id: topic_id) }
        # Reload so the snapshot carries the topic and allowed organization rows written above.
        Events::Publication.record!(event.reload) if event.status == "published"
      end

      # After commit: the model's after_commit clears this key, and a rolled-back event must never be cached.
      Events::Cache.write_detail(event.reload)
      event
    end

    private

    def id_list(value)
      Array(value).compact_blank.map(&:to_i).uniq
    end

    # Checked before insert so bad ids return 422 instead of reaching a foreign key.
    def validate!(event, allowed_ids, topic_ids)
      event.validate
      if event.errors[:status].empty? && !CREATABLE_STATUSES.include?(event.status)
        event.errors.add(:status, :inclusion, value: event.status)
      end
      Events::AllowedOrganizations.validate(event, allowed_ids, visibility: event.visibility)
      event.errors.add(:topic_ids, :invalid) if Topic.where(id: topic_ids).count != topic_ids.size

      raise ActiveRecord::RecordInvalid, event if event.errors.any?
    end
  end
end
