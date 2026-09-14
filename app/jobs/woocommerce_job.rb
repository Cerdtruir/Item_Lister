# ==============================================================================
# WoocommerceJob
#
# Purpose:
#   Generates the complete WooCommerce product import CSV (`public/woocommerce_items.csv`)
#   from local inventory items.
#
# COMPLETE EXECUTION FLOW:
#   STEP 1: Define WooCommerce CSV header schema.
#   STEP 2: Open target CSV file for writing.
#   STEP 3: Iterate through all inventory items:
#             - Determine stock status (1 for in-stock, 0 for out-of-stock).
#             - Determine item condition attribute ('New' or 'Unsealed/Used').
#             - Build clean category list (e.g. "Computers & Tablets, New").
#             - Set regular price directly from selling price (no discount markup).
#             - Set clean short description (item summary, no discount notices).
#             - Write formatted product row to CSV.
#   STEP 4: Finish writing and close file.
# ==============================================================================
class WoocommerceJob < ApplicationJob
  queue_as :default

  def perform
    # STEP 1: Define WooCommerce standard product CSV headers
    headers = [
      'SKU', 'Type', 'Name', 'Published', 'Is featured?', 'Visibility in catalog',
      'Short description', 'Description', 'Tax status', 'In stock?', 'Stock',
      'Backorders allowed?', 'Sold individually?', 'Allow customer reviews?',
      'Sale price', 'Regular price', 'Categories', 'Images',
      'Attribute 1 name', 'Attribute 1 value', 'Attribute 1 visible'
    ]

    # STEP 2 & 3: Open CSV and write product records
    CSV.open('public/woocommerce_items.csv', 'w', write_headers: true, headers: headers) do |writer|
      Item.find_each do |item|
        # Stock status flag
        in_stock = item.quantity.to_i.positive? ? 1 : 0

        # Standardized condition label
        condition = if item.condition.to_s.include?('Demo') || item.condition.to_s.include?('Unsealed')
                      'Unsealed/Used'
                    else
                      'New'
                    end

        # Map to actual item category and condition
        category_parts = []
        category_parts << item.category.to_s.strip if item.category.present?
        category_parts << condition
        categories = category_parts.uniq.join(', ')
        categories = 'Products, New' if categories.blank?

        # Clean pricing (direct selling price without artificial markup)
        regular_price = item.selling_price.to_f

        # Clean product title
        product_name = [item.name, item.condition].compact_blank.join(' - ')

        # Cloudinary product image URL
        image_url = "https://res.cloudinary.com/dwi7jdore/image/upload/#{item.id}.jpg"

        # Write clean product row
        writer << [
          item.id,
          'simple',
          product_name,
          1, # Published
          0, # Is featured
          'visible', # Catalog visibility
          item.name, # Clean short description (no discount text)
          "#{item.description} - #{item.condition}",
          'taxable',
          in_stock,
          item.quantity.to_i,
          0, # Backorders allowed
          0, # Sold individually
          1, # Allow reviews
          '', # Sale price (none)
          regular_price, # Regular price (exact selling price)
          categories,
          image_url,
          'Condition',
          condition,
          0
        ]
      end
    end
  end
end

