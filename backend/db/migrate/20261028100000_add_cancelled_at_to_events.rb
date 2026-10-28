class AddCancelledAtToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :cancelled_at, :datetime
  end
end
