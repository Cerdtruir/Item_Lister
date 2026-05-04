class WoocommerceJob < ApplicationJob
  queue_as :default

  def perform
    items = Item.all
    headers = ['SKU', 'Type', 'Name', 'Published', 'Is featured?', 'Visibility in catalog', 'Short description',
               'Description', 'Tax status', 'In stock?', 'Stock', 'Backorders allowed?', 'Sold individually?',
               'Allow customer reviews?', 'Sale price', 'Regular price', 'Categories', 'Images', 'Attribute 1 name', 'Attribute 1 value', 'Attribute 1 visible']
    CSV.open('public/woocommerce_items.csv', 'w', write_headers: true, headers:) do |writer|
      items.each do |item|
        in_stock = if item.quantity.zero?
                     0
                   else
                     1
                   end
        condition = if item.condition.include?('Demo') || item.condition.include?('Unsealed')
                      'Unsealed/Used'
                    else
                      'New'
                    end

        categories = "Products, #{condition}"
        regular_price = item.selling_price || 0
        regular_price = (regular_price * 1.035).round(2)
        regular_price = (regular_price / 25).round * 25 if regular_price >= 400

        writer << [item.id, 'simple', "#{item.name} - #{item.condition}", 1, 0, 'visible', 'Discount only available when paying by EFT', "#{item.description} - #{item.condition}",
                   'taxable', in_stock, item.quantity, 0, 0, 1, item.selling_price, regular_price, categories, "https://res.cloudinary.com/dwi7jdore/image/upload/#{item.id}.jpg", 'Condition', condition, 0]
      end
    end
  end
end
