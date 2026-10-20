class AddEventTextTrigramIndexes < ActiveRecord::Migration[7.1]
  def change
    enable_extension "pg_trgm"

    add_index :events, :title,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: "index_events_on_title_trgm"
    add_index :events, :description,
              using: :gin,
              opclass: :gin_trgm_ops,
              name: "index_events_on_description_trgm"
  end
end
