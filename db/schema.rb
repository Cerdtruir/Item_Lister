# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_09_16_154210) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "items", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "condition"
    t.integer "quantity"
    t.float "cost_price"
    t.float "selling_price"
    t.string "image"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "external_stock"
    t.string "category"
    t.decimal "original_price"
    t.boolean "takealot_condition"
    t.string "takealot_url"
    t.string "barcode"
    t.boolean "listed_on_takealot", default: false, null: false
    t.boolean "listed_on_woocommerce", default: false, null: false
    t.boolean "listed_on_amazon", default: false, null: false
    t.string "takealot_offer_id"
    t.string "woocommerce_product_id"
    t.string "amazon_asin"
    t.integer "takealot_stock"
    t.integer "woocommerce_stock"
    t.integer "amazon_stock"
    t.datetime "last_synced_at"
    t.boolean "listed_on_zoho", default: false, null: false
    t.string "zoho_item_id"
    t.integer "zoho_stock"
    t.text "notes"
    t.index ["barcode"], name: "index_items_on_barcode", unique: true
  end

  create_table "platform_settings", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_platform_settings_on_name", unique: true
  end

end
