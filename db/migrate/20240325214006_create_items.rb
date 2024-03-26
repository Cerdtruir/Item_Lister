class CreateItems < ActiveRecord::Migration[7.0]
  def change
    create_table :items do |t|
      t.string :name
      t.text :description
      t.string :condition
      t.integer :quantity
      t.float :cost_price
      t.float :selling_price
      t.string :image

      t.timestamps
    end
  end
end
