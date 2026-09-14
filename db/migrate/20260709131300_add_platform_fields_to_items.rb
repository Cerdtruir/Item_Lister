class AddPlatformFieldsToItems < ActiveRecord::Migration[7.0]
  def change
    add_column :items, :listed_on_takealot,     :boolean, default: false, null: false
    add_column :items, :listed_on_woocommerce,  :boolean, default: false, null: false
    add_column :items, :listed_on_amazon,       :boolean, default: false, null: false
    add_column :items, :takealot_offer_id,      :string
    add_column :items, :woocommerce_product_id, :string
    add_column :items, :amazon_asin,            :string
    add_column :items, :takealot_stock,         :integer
    add_column :items, :woocommerce_stock,      :integer
    add_column :items, :amazon_stock,           :integer
    add_column :items, :last_synced_at,         :datetime
  end
end
