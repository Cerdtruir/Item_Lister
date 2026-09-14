# frozen_string_literal: true

# ==============================================================================
# WooCommerce Management Rake Tasks
#
# Usage:
#   rails woocommerce:sync_categories   # Syncs/creates all DB categories on WooCommerce
#   rails woocommerce:push_items        # Pushes and updates inventory items on WooCommerce
#   rails woocommerce:sync_stock        # 2-way stock quantity sync
#   rails woocommerce:clean_discounts   # Strips leftover discount strings and fixes prices
#   rails woocommerce:generate_csv      # Generates public/woocommerce_items.csv
#   rails woocommerce:sync_all          # Complete category, product, and stock synchronization
# ==============================================================================

namespace :woocommerce do
  desc 'Sync all product categories from Item records to WooCommerce'
  task sync_categories: :environment do
    puts '=== [WooCommerce] Syncing Categories ==='
    map = WoocommerceSyncService.new.sync_categories
    puts "Categories synced successfully (#{map.size} available in WooCommerce):"
    map.each { |name, id| puts "  - #{name.titleize} (WC ID: #{id})" }
  end

  desc 'Push and update inventory items on WooCommerce with clean prices and categories'
  task push_items: :environment do
    puts '=== [WooCommerce] Pushing Inventory Items to WooCommerce ==='
    result = WoocommerceSyncService.new.push_items
    puts "Push complete: #{result[:created]} created, #{result[:updated]} updated, #{result[:failed]} failed."
  end

  desc 'Perform bidirectional stock sync with WooCommerce'
  task sync_stock: :environment do
    puts '=== [WooCommerce] Syncing Stock Quantities ==='
    summary = WoocommerceSyncService.new.sync
    puts "Stock sync complete: #{summary[:matched]} matched out of #{summary[:total_products]} remote products."
  end

  desc 'Clean any leftover discount text from WooCommerce products and normalize prices'
  task clean_discounts: :environment do
    puts '=== [WooCommerce] Cleaning Discount Text and Normalizing Prices ==='
    service = WoocommerceSyncService.new
    products = service.send(:fetch_all_published_products)
    puts "Retrieved #{products.size} published products from WooCommerce."

    updates = []
    products.each do |p|
      short_desc = p['short_description'].to_s
      sale_price = p['sale_price'].to_s.strip
      regular_price = p['regular_price'].to_s.strip

      needs_update = false
      update_data = { id: p['id'] }

      if short_desc.include?('Discount only available when paying by EFT') || short_desc.include?('Discount')
        cleaned_desc = short_desc.gsub(/<p>\s*Discount only available when paying by EFT\s*<\/p>/i, '')
                                 .gsub(/Discount only available when paying by EFT/i, '')
                                 .strip
        update_data[:short_description] = cleaned_desc
        needs_update = true
      end

      if !sale_price.empty? && !regular_price.empty? && sale_price != regular_price
        update_data[:regular_price] = sale_price
        update_data[:sale_price] = ''
        needs_update = true
      end

      updates << update_data if needs_update
    end

    if updates.any?
      puts "Updating #{updates.size} products..."
      updates.each_slice(50) do |slice|
        response = HTTParty.post(
          "#{WoocommerceSyncService::SITE_URL}/wp-json/wc/v3/products/batch",
          basic_auth: service.send(:auth_credentials),
          headers:    { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
          body:       { update: slice }.to_json,
          timeout:    60
        )
        puts "Batch of #{slice.size} -> HTTP #{response.code}"
      end
    else
      puts 'All products are already clean of discount text.'
    end
    puts 'Discounts cleanup complete!'
  end

  desc 'Generate public/woocommerce_items.csv for bulk export'
  task generate_csv: :environment do
    puts '=== [WooCommerce] Generating Items CSV ==='
    WoocommerceJob.perform_now
    puts 'Generated public/woocommerce_items.csv successfully.'
  end

  desc 'Complete WooCommerce sync: categories, products, and stock'
  task sync_all: :environment do
    puts '=== [WooCommerce] Full Sync: Categories, Items, and Stock ==='
    service = WoocommerceSyncService.new
    puts 'Step 1: Syncing categories...'
    service.sync_categories
    puts 'Step 2: Pushing items...'
    service.push_items
    puts 'Step 3: Syncing stock...'
    service.sync
    puts '=== Full WooCommerce Sync Complete! ==='
  end
end
