json.extract! item, :id, :name, :description, :condition, :quantity, :cost_price, :selling_price, :image, :created_at, :updated_at
json.url item_url(item, format: :json)
