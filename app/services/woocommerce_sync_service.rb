# frozen_string_literal: true

# ==============================================================================
# WoocommerceSyncService
#
# Purpose:
#   Comprehensive 2-way synchronization between local inventory and the
#   WooCommerce store (thedealsite.co.za) via the WooCommerce REST API v3.
#
# KEY CAPABILITIES:
#   1. `sync`: Bidirectional stock sync (pulls WC stock, pushes local stock).
#   2. `sync_categories`: Automatically provisions all local categories in WooCommerce.
#   3. `push_items`: Creates or updates product listings in WooCommerce with clean
#      prices, accurate categories, condition attributes, and Cloudinary images.
#
# AUTHENTICATION:
#   Supports either WordPress Application Passwords (WORDPRESS_USERNAME &
#   WORDPRESS_APP_PASSWORD) or WooCommerce REST API keys (WOOCOMMERCE_CONSUMER_KEY &
#   WOOCOMMERCE_CONSUMER_SECRET).
#
# COMPLETE EXECUTION FLOW FOR STOCK SYNC (`sync`):
#   STEP 1: Validate WooCommerce API credentials.
#   STEP 2: Fetch all published products from WooCommerce.
#   STEP 3: Index remote products by SKU and ID for fast lookup.
#   STEP 4: Bidirectional Sync Loop (PULL stock to DB, PUSH local quantity to WC).
#   STEP 5: Return summary statistics ({ matched: count, total_products: count }).
# ==============================================================================
class WoocommerceSyncService
  SITE_URL        = ENV.fetch('WOOCOMMERCE_URL', 'https://thedealsite.co.za')
  CONSUMER_KEY    = ENV.fetch('WOOCOMMERCE_CONSUMER_KEY', '')
  CONSUMER_SECRET = ENV.fetch('WOOCOMMERCE_CONSUMER_SECRET', '')
  WP_USERNAME     = ENV.fetch('WORDPRESS_USERNAME', 'aqdw8yih')
  WP_APP_PASSWORD = ENV.fetch('WORDPRESS_APP_PASSWORD', '2dXn OEb7 HmoH apeo b889 hX6x')

  # ============================================================================
  # 1. STOCK SYNC (Bidirectional)
  # ============================================================================
  def sync
    Rails.logger.info '[WooCommerceSync] =========================================='
    Rails.logger.info '[WooCommerceSync] STEP 1: Validating API credentials...'
    unless configured?
      Rails.logger.warn '[WooCommerceSync] Skipped — API credentials not configured.'
      return { matched: 0, total_products: 0, skipped: true }
    end

    # --------------------------------------------------------------------------
    # STEP 2: Fetch all published products from WooCommerce
    # --------------------------------------------------------------------------
    Rails.logger.info '[WooCommerceSync] STEP 2: Fetching products from WooCommerce REST API...'
    products = fetch_all_published_products
    Rails.logger.info "[WooCommerceSync] Retrieved #{products.size} published products."

    # --------------------------------------------------------------------------
    # STEP 3: Index remote products by SKU and ID
    # --------------------------------------------------------------------------
    Rails.logger.info '[WooCommerceSync] STEP 3: Indexing WooCommerce products by SKU and ID...'
    product_by_sku = products.index_by { |p| p['sku'].to_s.strip }
    product_by_id  = products.index_by { |p| p['id'].to_s }

    # --------------------------------------------------------------------------
    # STEP 4: Bidirectional sync (PULL status/stock into DB, PUSH local quantity)
    # --------------------------------------------------------------------------
    Rails.logger.info '[WooCommerceSync] STEP 4: Performing 2-way sync with local items...'
    matched_count = 0

    Item.find_each do |item|
      begin
        barcode_key = item.barcode.to_s.strip
        id_key      = item.id.to_s
        wc_id_key   = item.woocommerce_product_id.to_s

        # Match by barcode, local ID, or saved WooCommerce product ID
        product = (barcode_key.present? ? product_by_sku[barcode_key] : nil) ||
                  product_by_sku[id_key] ||
                  (wc_id_key.present? ? product_by_id[wc_id_key] : nil)

        if product
          remote_stock = product['stock_quantity'].to_i
          product_id   = product['id'].to_s

          # PULL: Update local record with WooCommerce ID and remote stock
          item.update_columns(
            listed_on_woocommerce:  true,
            woocommerce_product_id: product_id,
            woocommerce_stock:      remote_stock
          )

          # PUSH: Send our current warehouse quantity to WooCommerce
          local_quantity = item.quantity.to_i
          push_stock_to_woocommerce(product_id, local_quantity)

          matched_count += 1
        else
          # Item not present on WooCommerce -> clear listed flag if set
          if item.listed_on_woocommerce? || item.woocommerce_stock.present?
            item.update_columns(listed_on_woocommerce: false, woocommerce_stock: nil)
          end
        end
      rescue StandardError => e
        # Isolate item-level error so sync continues for remaining items
        Rails.logger.warn "[WooCommerceSync] Error processing Item ##{item.id}: #{e.message}"
      end
    end

    # --------------------------------------------------------------------------
    # STEP 5: Return summary
    # --------------------------------------------------------------------------
    Rails.logger.info "[WooCommerceSync] STEP 5: Stock sync complete! #{matched_count} items matched."
    Rails.logger.info '[WooCommerceSync] =========================================='
    { matched: matched_count, total_products: products.size }
  rescue StandardError => e
    Rails.logger.error "[WooCommerceSync] Fatal error during sync: #{e.message}"
    raise
  end

  # ============================================================================
  # 2. CATEGORY SYNCHRONIZATION
  #
  # Ensures all distinct item categories from the database exist in WooCommerce.
  # Returns a map: { "Category Name" => category_id }
  # ============================================================================
  def sync_categories
    Rails.logger.info '[WooCommerceCategorySync] === STARTING CATEGORY SYNC ==='
    unless configured?
      Rails.logger.warn '[WooCommerceCategorySync] API credentials not configured.'
      return {}
    end

    # STEP 1: Fetch existing categories from WooCommerce
    existing_categories = fetch_all_categories
    category_map = existing_categories.each_with_object({}) do |cat, map|
      map[cat['name'].to_s.strip.downcase] = cat['id']
    end

    # STEP 2: Collect all distinct categories from local items
    local_categories = Item.distinct.pluck(:category).compact_blank.map(&:strip).uniq
    condition_categories = ['New', 'Unsealed/Used']
    all_needed = (local_categories + condition_categories).uniq

    Rails.logger.info "[WooCommerceCategorySync] Verifying #{all_needed.size} categories..."

    # STEP 3: Create any missing categories in WooCommerce
    all_needed.each do |cat_name|
      key = cat_name.downcase
      next if category_map.key?(key)

      begin
        created = create_category(cat_name)
        if created && created['id']
          category_map[key] = created['id']
          Rails.logger.info "[WooCommerceCategorySync] Created category '#{cat_name}' (ID: #{created['id']})"
        end
      rescue StandardError => e
        Rails.logger.warn "[WooCommerceCategorySync] Failed to create category '#{cat_name}': #{e.message}"
      end
    end

    Rails.logger.info "[WooCommerceCategorySync] === CATEGORY SYNC COMPLETE (#{category_map.size} total) ==="
    category_map
  end

  # ============================================================================
  # 3. PUSH ITEMS TO WOOCOMMERCE
  #
  # Pushes items to WooCommerce with clean pricing, real categories, and images.
  # Uses batch API for high throughput.
  # ============================================================================
  def push_items(scope = Item.where.not(selling_price: [nil, 0]))
    Rails.logger.info '[WooCommercePush] === STARTING ITEM PUSH TO WOOCOMMERCE ==='
    unless configured?
      Rails.logger.warn '[WooCommercePush] API credentials not configured.'
      return { created: 0, updated: 0, failed: 0 }
    end

    # STEP 1: Ensure categories exist and get mapping
    category_map = sync_categories

    # STEP 2: Fetch existing products and index by SKU and ID
    products = fetch_all_published_products
    product_by_sku = products.index_by { |p| p['sku'].to_s.strip }
    product_by_id  = products.index_by { |p| p['id'].to_s }

    created_count = 0
    updated_count = 0
    failed_count  = 0

    # STEP 3: Process items in batches of 50
    scope.find_in_batches(batch_size: 50) do |batch|
      batch_payload = { create: [], update: [] }
      item_by_payload_sku = {}

      batch.each do |item|
        begin
          barcode_key = item.barcode.to_s.strip
          id_key      = item.id.to_s
          wc_id_key   = item.woocommerce_product_id.to_s

          product = (barcode_key.present? ? product_by_sku[barcode_key] : nil) ||
                    product_by_sku[id_key] ||
                    (wc_id_key.present? ? product_by_id[wc_id_key] : nil)

          # Prepare condition label
          condition_label = if item.condition.to_s.include?('Demo') || item.condition.to_s.include?('Unsealed')
                              'Unsealed/Used'
                            else
                              'New'
                            end

          # Determine categories
          cat_ids = []
          if item.category.present?
            cat_id = category_map[item.category.to_s.strip.downcase]
            cat_ids << { id: cat_id } if cat_id
          end
          cond_id = category_map[condition_label.downcase]
          cat_ids << { id: cond_id } if cond_id

          # Build clean product payload (regular_price = selling_price, NO discounts)
          product_name = [item.name, item.condition].compact_blank.join(' - ')
          image_url    = "https://res.cloudinary.com/dwi7jdore/image/upload/#{item.id}.jpg"
          sku          = barcode_key.presence || id_key

          item_payload = {
            name:              product_name,
            description:       "#{item.description} - #{item.condition}",
            short_description: item.name.to_s,
            regular_price:     item.selling_price.to_f.to_s,
            sale_price:        '',
            manage_stock:      true,
            stock_quantity:    item.quantity.to_i,
            categories:        cat_ids,
            images:            [{ src: image_url }],
            attributes: [
              {
                name: 'Condition',
                visible: true,
                options: [condition_label]
              }
            ]
          }

          if product
            # Existing product -> update
            item_payload[:id] = product['id']
            batch_payload[:update] << item_payload
            item_by_payload_sku[product['id'].to_s] = item
          else
            # New product -> create
            item_payload[:sku]    = sku
            item_payload[:status] = 'publish'
            batch_payload[:create] << item_payload
            item_by_payload_sku[sku] = item
          end
        rescue StandardError => e
          failed_count += 1
          Rails.logger.warn "[WooCommercePush] Error formatting Item ##{item.id}: #{e.message}"
        end
      end

      # STEP 4: Send batch request to WooCommerce
      if batch_payload[:create].any? || batch_payload[:update].any?
        begin
          response = HTTParty.post(
            "#{SITE_URL}/wp-json/wc/v3/products/batch",
            basic_auth: auth_credentials,
            headers:    { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
            body:       batch_payload.to_json,
            timeout:    60
          )

          if [200, 201].include?(response.code)
            result = response.parsed_response
            (result['create'] || []).each do |p|
              created_count += 1
              matched_item = item_by_payload_sku[p['sku'].to_s]
              if matched_item
                matched_item.update_columns(
                  listed_on_woocommerce:  true,
                  woocommerce_product_id: p['id'].to_s,
                  woocommerce_stock:      p['stock_quantity'].to_i
                )
              end
            end

            (result['update'] || []).each do |p|
              updated_count += 1
              matched_item = item_by_payload_sku[p['id'].to_s]
              if matched_item
                matched_item.update_columns(
                  listed_on_woocommerce:  true,
                  woocommerce_product_id: p['id'].to_s,
                  woocommerce_stock:      p['stock_quantity'].to_i
                )
              end
            end
          else
            failed_count += batch.size
            Rails.logger.error "[WooCommercePush] Batch request failed (HTTP #{response.code}): #{response.body}"
          end
        rescue StandardError => e
          failed_count += batch.size
          Rails.logger.error "[WooCommercePush] Batch execution error: #{e.message}"
        end
      end
    end

    Rails.logger.info "[WooCommercePush] Finished: #{created_count} created, #{updated_count} updated, #{failed_count} failed."
    { created: created_count, updated: updated_count, failed: failed_count }
  end

  private

  # Check if WooCommerce credentials are present
  def configured?
    (WP_USERNAME.present? && WP_APP_PASSWORD.present?) ||
      (CONSUMER_KEY.present? && CONSUMER_SECRET.present? && CONSUMER_KEY != 'your_consumer_key_here')
  end

  # Basic auth hash for HTTParty requests
  def auth_credentials
    if WP_USERNAME.present? && WP_APP_PASSWORD.present?
      { username: WP_USERNAME, password: WP_APP_PASSWORD }
    else
      { username: CONSUMER_KEY, password: CONSUMER_SECRET }
    end
  end

  # Helper: Fetch all categories from WooCommerce
  def fetch_all_categories
    all_cats = []
    page = 1
    loop do
      response = HTTParty.get(
        "#{SITE_URL}/wp-json/wc/v3/products/categories",
        basic_auth: auth_credentials,
        query:      { per_page: 100, page: page },
        headers:    { 'Accept' => 'application/json' },
        timeout:    30
      )
      break unless response.code == 200

      batch = response.parsed_response
      break if batch.blank? || !batch.is_a?(Array)

      all_cats.concat(batch)
      break if batch.size < 100

      page += 1
    end
    all_cats
  rescue StandardError => e
    Rails.logger.error "[WooCommerceSync] Error fetching categories: #{e.message}"
    []
  end

  # Helper: Create a category in WooCommerce
  def create_category(name)
    response = HTTParty.post(
      "#{SITE_URL}/wp-json/wc/v3/products/categories",
      basic_auth: auth_credentials,
      headers:    { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
      body:       { name: name }.to_json,
      timeout:    15
    )
    return response.parsed_response if [200, 201].include?(response.code)

    Rails.logger.warn "[WooCommerceSync] Failed to create category '#{name}' (HTTP #{response.code})"
    nil
  end

  # Helper: Fetch all published products page-by-page (100 products per page)
  def fetch_all_published_products
    all_products = []
    page = 1

    loop do
      response = HTTParty.get(
        "#{SITE_URL}/wp-json/wc/v3/products",
        basic_auth: auth_credentials,
        query:      { per_page: 100, page: page, status: 'publish' },
        headers:    { 'Accept' => 'application/json' },
        timeout:    30
      )

      unless response.code == 200
        raise "WooCommerce API error HTTP #{response.code}: #{response.body}"
      end

      batch = response.parsed_response
      break if batch.blank? || !batch.is_a?(Array)

      all_products.concat(batch)
      break if batch.size < 100

      page += 1
    end

    all_products
  end

  # Helper: Push our local quantity to WooCommerce store
  def push_stock_to_woocommerce(product_id, quantity)
    response = HTTParty.put(
      "#{SITE_URL}/wp-json/wc/v3/products/#{product_id}",
      basic_auth: auth_credentials,
      headers:    { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
      body:       { stock_quantity: quantity, manage_stock: true }.to_json,
      timeout:    15
    )

    unless [200, 201].include?(response.code)
      Rails.logger.warn "[WooCommerceSync] Failed to push stock for product ##{product_id} (HTTP #{response.code})"
    end
  rescue StandardError => e
    Rails.logger.warn "[WooCommerceSync] Push stock error for product ##{product_id}: #{e.message}"
  end
end
