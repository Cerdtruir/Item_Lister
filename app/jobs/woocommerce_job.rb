class WoocommerceJob < ApplicationJob
  queue_as :default

  def perform
    require 'csv'

    # Fetch all items from the database
    items = Item.all
    headers = ['ID', 'Type', 'Name', 'Published', 'Is featured?', 'Visibility in catalog', 'Short description',
               'Description', 'Tax status', 'In stock?', 'Stock', 'Backorders allowed?', 'Sold individually?',
               'Allow customer reviews?', 'Regular price', 'Categories', 'Images']
    CSV.open('public/items.csv', 'w', write_headers: true, headers:) do |writer|
      items.each do |item|
        in_stock = if item.quantity.zero?
                     0
                   else
                     1
                   end

        writer << [item.id, 'simple', item.name, 1, 0, 'visible', item.description, item.description,
                   'taxable', in_stock, item.quantity, 0, 0, 1, item.selling_price, 'items', "https://res.cloudinary.com/dwi7jdore/image/upload/#{item.id}.jpg"]
      end
    end
  end
end
