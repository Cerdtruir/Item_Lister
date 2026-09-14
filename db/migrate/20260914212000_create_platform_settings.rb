# frozen_string_literal: true

class CreatePlatformSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :platform_settings do |t|
      t.string  :name,    null: false
      t.boolean :enabled, null: false, default: false

      t.timestamps
    end

    add_index :platform_settings, :name, unique: true
  end
end
