class AddTakealotUrlToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :takealot_url, :string
  end
end
