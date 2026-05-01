json.extract! item, :id, :name, :description, :condition, :quantity, :cost_price, :selling_price, :image, :created_at,
              :updated_at, :external_stock
json.url item_url(item, format: :json)
