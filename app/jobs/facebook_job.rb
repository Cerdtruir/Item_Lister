class FacebookJob < ApplicationJob
  queue_as :default

  def perform
    items = Item.where('quantity > ?', 0).order(:id).reverse
    headers = ['Title', 'Photos Folder', 'Photos Names', 'Price', 'Category', 'Condition', 'Brand', 'Description',
               'Location', 'Groups', 'Stock']
    CSV.open('public/facebook_items.csv', 'w', write_headers: true, headers:) do |writer|
      items.each do |item|
        # Item.where(id: 214)

        name = item.name.gsub('"', '')

        description = "#{item.name}" # Assuming 'stock' is an attribute of the Item model
        description += "\n\nOriginal invoice available."
        description += "\n\nView my website at https://thedealsite.co.za/"
        description += "\n\nView my bobshop reviews and items at: https://www.bobshop.co.za/user/1475301/The_Deal_Site"
        description += "\n\nMore than 1 available" if item.quantity > 1

        condition = if item.condition.include?('Demo')
                      'Used – like new'
                    else
                      'New'
                    end

        writer << ["#{item.condition} - #{name}", '/home/n/github-repos/Item_Lister/public', "#{item.id}.jpg", item.selling_price.to_i,
                   'Miscellaneous', condition, '', description, 'Kyalami AH, South Africa', 'Marketplace', item.quantity]
      end
    end
  end
end
