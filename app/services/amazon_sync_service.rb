# frozen_string_literal: true

# ==============================================================================
# AmazonSyncService
#
# Purpose:
#   Synchronize local inventory with Amazon.co.za via the Selling Partner API
#   (SP-API). Reads product listing status, ASIN, and fulfillment stock.
#
# MATCHING LOGIC:
#   Amazon stores EAN barcodes in the listing attributes under:
#     `attributes.externally_assigned_product_identifier`
#   We match this EAN against our local `item.barcode`.
#
# COMPLETE EXECUTION FLOW:
#   STEP 1: Validate Amazon SP-API credentials in .env
#   STEP 2: Exchange refresh token for a short-lived LWA access token (POST /auth/o2/token)
#   STEP 3: Fetch active listings from SP-API (paginated GET /listings/2021-08-01/items/:seller_id)
#   STEP 4: Extract EAN barcodes and index listings: { ean => listing }
#   STEP 5: Match local items against the index:
#             - If matched on Amazon:
#                 * listed_on_amazon = true
#                 * amazon_asin      = ASIN
#                 * amazon_stock     = total quantity across fulfillmentAvailability
#             - If NOT on Amazon:
#                 * listed_on_amazon = false
#                 * amazon_stock     = nil
#   STEP 6: Return summary statistics ({ matched: count, total_listings: count })
# ==============================================================================
class AmazonSyncService
  MARKETPLACE_ID = ENV.fetch('AMAZON_MARKETPLACE_ID', 'A1AM78C64UM0Y8') # Amazon.co.za
  SELLER_ID      = ENV.fetch('AMAZON_SELLER_ID', '')
  CLIENT_ID      = ENV.fetch('AMAZON_CLIENT_ID', '')
  CLIENT_SECRET  = ENV.fetch('AMAZON_CLIENT_SECRET', '')
  REFRESH_TOKEN  = ENV.fetch('AMAZON_REFRESH_TOKEN', '')
  TOKEN_URL      = 'https://api.amazon.com/auth/o2/token'
  SP_API_BASE    = 'https://sellingpartnerapi-eu.amazon.com'

  def sync
    Rails.logger.info '[AmazonSync] =========================================='
    Rails.logger.info '[AmazonSync] STEP 1: Validating Amazon SP-API credentials...'
    unless configured?
      Rails.logger.warn '[AmazonSync] Skipped — Amazon credentials not configured in .env'
      return { matched: 0, total_listings: 0, skipped: true }
    end

    # --------------------------------------------------------------------------
    # STEP 2: Authenticate via Login with Amazon (LWA)
    # --------------------------------------------------------------------------
    Rails.logger.info '[AmazonSync] STEP 2: Requesting LWA access token...'
    access_token = fetch_access_token

    # --------------------------------------------------------------------------
    # STEP 3: Fetch all listings from Amazon SP-API (handles pagination)
    # --------------------------------------------------------------------------
    Rails.logger.info '[AmazonSync] STEP 3: Fetching listings from SP-API...'
    listings = fetch_all_listings(access_token)
    Rails.logger.info "[AmazonSync] Retrieved #{listings.size} listings from Amazon."

    # --------------------------------------------------------------------------
    # STEP 4: Build index of listings by EAN barcode: { ean => listing }
    # Example Amazon listing item format:
    # {
    #   "asin" => "B0D7P1XYZ",
    #   "summaries" => [{ "asin" => "B0D7P1XYZ", "itemName" => "..." }],
    #   "attributes" => {
    #     "externally_assigned_product_identifier" => [
    #       { "type" => "EAN", "value" => "8806095647159" }
    #     ]
    #   },
    #   "fulfillmentAvailability" => [{ "quantity" => 8 }]
    # }
    # --------------------------------------------------------------------------
    Rails.logger.info '[AmazonSync] STEP 4: Indexing Amazon listings by EAN barcode...'
    listing_by_ean = {}

    listings.each do |listing|
      eans = extract_eans(listing)
      eans.each { |ean| listing_by_ean[ean] = listing }
    end

    # --------------------------------------------------------------------------
    # STEP 5: Match local database items with Amazon listings
    # --------------------------------------------------------------------------
    Rails.logger.info '[AmazonSync] STEP 5: Matching local inventory with Amazon listings...'
    matched_count = 0

    Item.where.not(barcode: [nil, '']).find_each do |item|
      barcode = item.barcode.to_s.strip
      listing = listing_by_ean[barcode]

      if listing
        asin  = extract_asin(listing)
        stock = extract_quantity(listing)

        item.update_columns(
          listed_on_amazon: true,
          amazon_asin:      asin,
          amazon_stock:     stock
        )
        matched_count += 1
      else
        # Item is NOT on Amazon -> clear listing flag if previously marked
        if item.listed_on_amazon? || item.amazon_stock.present?
          item.update_columns(listed_on_amazon: false, amazon_stock: nil)
        end
      end
    end

    # --------------------------------------------------------------------------
    # STEP 6: Return summary
    # --------------------------------------------------------------------------
    Rails.logger.info "[AmazonSync] STEP 6: Sync complete! #{matched_count} items matched on Amazon."
    Rails.logger.info '[AmazonSync] =========================================='
    { matched: matched_count, total_listings: listings.size }
  rescue StandardError => e
    Rails.logger.error "[AmazonSync] Error during sync: #{e.message}"
    raise
  end

  private

  # Check if all required SP-API credentials exist
  def configured?
    [SELLER_ID, CLIENT_ID, CLIENT_SECRET, REFRESH_TOKEN].all?(&:present?)
  end

  # ----------------------------------------------------------------------------
  # Helper: Exchange refresh token for LWA access token
  # POST https://api.amazon.com/auth/o2/token
  # ----------------------------------------------------------------------------
  def fetch_access_token
    response = HTTParty.post(
      TOKEN_URL,
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      body: {
        grant_type:    'refresh_token',
        refresh_token: REFRESH_TOKEN,
        client_id:     CLIENT_ID,
        client_secret: CLIENT_SECRET
      },
      timeout: 15
    )

    unless response.code == 200
      raise "Amazon LWA token error HTTP #{response.code}: #{response.body}"
    end

    response.parsed_response['access_token']
  end

  # ----------------------------------------------------------------------------
  # Helper: Fetch all seller listings using cursor pagination (nextPageToken)
  # GET /listings/2021-08-01/items/:seller_id
  # ----------------------------------------------------------------------------
  def fetch_all_listings(access_token)
    all_items = []
    page_token = nil

    loop do
      params = {
        marketplaceIds: MARKETPLACE_ID,
        pageSize:       20,
        includedData:   'summaries,attributes,fulfillmentAvailability'
      }
      params[:pageToken] = page_token if page_token.present?

      response = HTTParty.get(
        "#{SP_API_BASE}/listings/2021-08-01/items/#{SELLER_ID}",
        query:   params,
        headers: {
          'x-amz-access-token' => access_token,
          'Accept'             => 'application/json'
        },
        timeout: 30
      )

      unless response.code == 200
        raise "Amazon SP-API listings error HTTP #{response.code}: #{response.body}"
      end

      body = response.parsed_response
      items = body['items'] || []
      all_items.concat(items)

      # Follow pagination cursor if present; otherwise, we are done
      page_token = body.dig('pagination', 'nextPageToken')
      break if page_token.blank?
    end

    all_items
  end

  # ----------------------------------------------------------------------------
  # Helper: Extract all EAN barcodes attached to an Amazon listing
  # ----------------------------------------------------------------------------
  def extract_eans(listing)
    identifiers = listing.dig('attributes', 'externally_assigned_product_identifier') || []
    return [] unless identifiers.is_a?(Array)

    identifiers
      .select { |id| id['type'].to_s.upcase == 'EAN' }
      .map { |id| id['value'].to_s.strip }
  end

  # ----------------------------------------------------------------------------
  # Helper: Extract ASIN from summaries or top-level listing
  # ----------------------------------------------------------------------------
  def extract_asin(listing)
    listing.dig('summaries', 0, 'asin') || listing['asin']
  end

  # ----------------------------------------------------------------------------
  # Helper: Sum total available quantity from fulfillmentAvailability
  # Format: "fulfillmentAvailability": [ { "quantity": 5 } ]
  # ----------------------------------------------------------------------------
  def extract_quantity(listing)
    availability = listing['fulfillmentAvailability'] || []
    return nil unless availability.is_a?(Array)

    availability.sum { |entry| entry['quantity'].to_i }
  end
end
