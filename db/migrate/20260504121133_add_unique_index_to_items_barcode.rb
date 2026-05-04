class AddUniqueIndexToItemsBarcode < ActiveRecord::Migration[7.0]
  def change
    add_index :items, :barcode, unique: true
  end
end
