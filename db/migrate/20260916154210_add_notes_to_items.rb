class AddNotesToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :notes, :text
  end
end
