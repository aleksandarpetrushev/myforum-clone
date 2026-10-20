class AddEventTextTrigramIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :events, :title, **trigram_index("index_events_on_title_trgm"), if_not_exists: true
    add_index :events, :description, **trigram_index("index_events_on_description_trgm"), if_not_exists: true
  end

  def down
    remove_index :events, name: "index_events_on_description_trgm", algorithm: :concurrently, if_exists: true
    remove_index :events, name: "index_events_on_title_trgm", algorithm: :concurrently, if_exists: true
    disable_extension "pg_trgm" if extension_enabled?("pg_trgm")
  end

  private

  def trigram_index(name)
    {
      using: :gin,
      opclass: :gin_trgm_ops,
      algorithm: :concurrently,
      name: name
    }
  end
end
