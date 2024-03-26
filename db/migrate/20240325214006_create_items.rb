class CreateItems < ActiveRecord::Migration[7.0]
  def change
    create_table :items do |t|
      t.string :name
      t.text :description
      t.string :condition
      t.string :quantity
      t.string :cost_price
      t.string :selling_price
      t.string :image

      t.timestamps
    end
  end
end
