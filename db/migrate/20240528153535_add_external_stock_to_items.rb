class AddExternalStockToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :external_stock, :integer
  end
end
