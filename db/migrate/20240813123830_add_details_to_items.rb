class AddDetailsToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :category, :string
    add_column :items, :original_price, :decimal
    add_column :items, :takealot_condition, :boolean
  end
end
