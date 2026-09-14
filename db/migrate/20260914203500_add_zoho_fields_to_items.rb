class AddZohoFieldsToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :listed_on_zoho, :boolean, default: false, null: false
    add_column :items, :zoho_item_id,   :string
    add_column :items, :zoho_stock,     :integer
  end
end
