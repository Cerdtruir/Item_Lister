# frozen_string_literal: true

# ==============================================================================
# ZohoSyncService
#
# Purpose:
#   Synchronize local inventory with Zoho Inventory via the Zoho Inventory REST API.
#   Reads product listing status, Zoho item ID, and stock-on-hand levels.
#
# MATCHING LOGIC:
#   Zoho Inventory items have a `sku` (and optional `ean` / `upc`) field that
#   corresponds to our local `item.barcode`.
#
# COMPLETE EXECUTION FLOW:
#   STEP 1: Validate Zoho API credentials in .env
#   STEP 2: Authenticate via OAuth 2.0 refresh token grant to obtain a short-lived
#           access token (POST /oauth/v2/token)
#   STEP 3: Resolve Organization ID (from ENV or auto-discovered via GET /organizations)
#   STEP 4: Fetch all active items from Zoho Inventory (paginated GET /items)
#   STEP 5: Index remote items by SKU, EAN, and UPC for fast O(1) matching: { sku => item }
#   STEP 6: Match local items against the index:
#             - If matched on Zoho:
#                 * listed_on_zoho = true
#                 * zoho_item_id   = item['item_id']
#                 * zoho_stock     = item['stock_on_hand']
#             - If NOT on Zoho:
#                 * listed_on_zoho = false
#                 * zoho_stock     = nil
#   STEP 7: Return summary statistics ({ matched: count, total_items: count })
# ==============================================================================
class ZohoSyncService
  CLIENT_ID       = ENV.fetch('ZOHO_CLIENT_ID', '1000.9Q9VBQGI1457GA3HZP60N2HOZ3D6ZN')
  CLIENT_SECRET   = ENV.fetch('ZOHO_CLIENT_SECRET', '3aa1c685701de3a7a4a1ad09368e78f87765221553')
  REFRESH_TOKEN   = ENV.fetch('ZOHO_REFRESH_TOKEN', '')
  ORGANIZATION_ID = ENV.fetch('ZOHO_ORGANIZATION_ID', '')
  ACCOUNTS_URL    = ENV.fetch('ZOHO_ACCOUNTS_URL', 'https://accounts.zoho.com')
  API_BASE_URL    = ENV.fetch('ZOHO_API_BASE_URL', 'https://www.zohoapis.com/inventory/v1')

  def sync
    Rails.logger.info '[ZohoSync] =========================================='
    Rails.logger.info '[ZohoSync] STEP 1: Checking API credentials...'
    unless configured?
      missing = missing_credentials.join(', ')
      Rails.logger.warn "[ZohoSync] Skipped — Missing required Zoho credentials in .env: #{missing}"
      return { matched: 0, total_items: 0, skipped: true }
    end

    # --------------------------------------------------------------------------
    # STEP 2: Authenticate via OAuth 2.0 refresh token grant
    # --------------------------------------------------------------------------
    Rails.logger.info '[ZohoSync] STEP 2: Requesting OAuth access token...'
    access_token = fetch_access_token

    # --------------------------------------------------------------------------
    # STEP 3: Resolve Organization ID (configured or auto-discovered)
    # --------------------------------------------------------------------------
    Rails.logger.info '[ZohoSync] STEP 3: Resolving Zoho Organization ID...'
    org_id = resolve_organization_id(access_token)
    unless org_id.present?
      Rails.logger.error '[ZohoSync] FAILED: Could not resolve a valid Zoho Organization ID.'
      return { matched: 0, total_items: 0, error: 'Organization ID not found' }
    end
    Rails.logger.info "[ZohoSync] Using Organization ID: #{org_id}"

    # --------------------------------------------------------------------------
    # STEP 4: Fetch all items from Zoho Inventory (handles pagination)
    # --------------------------------------------------------------------------
    Rails.logger.info '[ZohoSync] STEP 4: Fetching items from Zoho Inventory API...'
    zoho_items = fetch_all_items(access_token, org_id)
    Rails.logger.info "[ZohoSync] Retrieved #{zoho_items.size} items from Zoho Inventory."

    # --------------------------------------------------------------------------
    # STEP 5: Index items by SKU and barcode identifiers for fast O(1) matching
    # Example Zoho item structure:
    # {
    #   "item_id": "4815000000044208",
    #   "name": "Bags-small",
    #   "sku": "6009544507574",
    #   "upc": "6009544507574",
    #   "ean": "6009544507574",
    #   "status": "active",
    #   "stock_on_hand": 50
    # }
    # --------------------------------------------------------------------------
    Rails.logger.info '[ZohoSync] STEP 5: Indexing Zoho items by SKU/Barcode...'
    item_index = build_item_index(zoho_items)

    # --------------------------------------------------------------------------
    # STEP 6: Compare and match local database items against Zoho index
    # --------------------------------------------------------------------------
    Rails.logger.info '[ZohoSync] STEP 6: Matching local items against Zoho Inventory...'
    matched_count = 0

    Item.where.not(barcode: [nil, '']).find_each do |item|
      barcode   = item.barcode.to_s.strip
      zoho_item = item_index[barcode]

      if zoho_item
        # Item IS listed on Zoho Inventory -> update listing flag, item ID, and stock
        stock = zoho_item['stock_on_hand'].to_i
        item.update_columns(
          listed_on_zoho: true,
          zoho_item_id:   zoho_item['item_id'].to_s,
          zoho_stock:     stock
        )
        matched_count += 1
      else
        # Item is NOT on Zoho -> clear listed flag if previously set
        if item.listed_on_zoho? || item.zoho_stock.present?
          item.update_columns(listed_on_zoho: false, zoho_stock: nil)
        end
      end
    end

    # --------------------------------------------------------------------------
    # STEP 7: Return summary
    # --------------------------------------------------------------------------
    Rails.logger.info "[ZohoSync] STEP 7: Sync complete! #{matched_count} items matched on Zoho Inventory."
    Rails.logger.info '[ZohoSync] =========================================='
    { matched: matched_count, total_items: zoho_items.size }
  rescue StandardError => e
    Rails.logger.error "[ZohoSync] Error during sync: #{e.message}"
    raise
  end

  private

  # Check if minimal required credentials exist
  def configured?
    CLIENT_ID.present? && CLIENT_SECRET.present? && REFRESH_TOKEN.present?
  end

  def missing_credentials
    missing = []
    missing << 'ZOHO_CLIENT_ID' if CLIENT_ID.blank?
    missing << 'ZOHO_CLIENT_SECRET' if CLIENT_SECRET.blank?
    missing << 'ZOHO_REFRESH_TOKEN' if REFRESH_TOKEN.blank?
    missing
  end

  # ----------------------------------------------------------------------------
  # Helper: Exchange refresh token for short-lived access token
  # POST https://accounts.zoho.com/oauth/v2/token
  # Expected Response:
  #   { "access_token": "1000.xxxx", "expires_in": 3600, "token_type": "Bearer" }
  # ----------------------------------------------------------------------------
  def fetch_access_token
    response = HTTParty.post(
      "#{ACCOUNTS_URL}/oauth/v2/token",
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      body: {
        grant_type:    'refresh_token',
        client_id:     CLIENT_ID,
        client_secret: CLIENT_SECRET,
        refresh_token: REFRESH_TOKEN
      },
      timeout: 15
    )

    unless response.code == 200
      raise "Zoho OAuth token error HTTP #{response.code}: #{response.body}"
    end

    token = response.parsed_response['access_token']
    raise "Zoho OAuth response missing access_token: #{response.body}" if token.blank?

    token
  end

  # ----------------------------------------------------------------------------
  # Helper: Resolve organization ID from ENV or by calling GET /organizations
  # Expected Organizations Response:
  #   { "code": 0, "organizations": [ { "organization_id": "70001", "is_default_org": true } ] }
  # ----------------------------------------------------------------------------
  def resolve_organization_id(access_token)
    return ORGANIZATION_ID if ORGANIZATION_ID.present?

    response = HTTParty.get(
      "#{API_BASE_URL}/organizations",
      headers: {
        'Authorization' => "Zoho-oauthtoken #{access_token}",
        'Accept'        => 'application/json'
      },
      timeout: 15
    )

    unless response.code == 200
      Rails.logger.warn "[ZohoSync] Failed to fetch organizations (HTTP #{response.code}): #{response.body}"
      return nil
    end

    orgs = response.parsed_response['organizations'] || []
    return nil if orgs.empty?

    # Prefer default org, fallback to first org
    default_org = orgs.find { |o| o['is_default_org'] == true } || orgs.first
    default_org['organization_id'].to_s
  end

  # ----------------------------------------------------------------------------
  # Helper: Fetch all items with pagination (per_page = 200)
  # GET /items?organization_id=...&page=N&per_page=200
  # Expected Response:
  #   {
  #     "code": 0,
  #     "items": [ { "item_id": "...", "sku": "...", "stock_on_hand": 5 } ],
  #     "page_context": { "page": 1, "has_more_page": false }
  #   }
  # ----------------------------------------------------------------------------
  def fetch_all_items(access_token, org_id)
    all_items = []
    page = 1

    loop do
      response = HTTParty.get(
        "#{API_BASE_URL}/items",
        query: {
          organization_id: org_id,
          page:            page,
          per_page:        200
        },
        headers: {
          'Authorization'                         => "Zoho-oauthtoken #{access_token}",
          'X-com-zoho-inventory-organizationid' => org_id,
          'Accept'                                => 'application/json'
        },
        timeout: 30
      )

      unless response.code == 200
        raise "Zoho Inventory API items error HTTP #{response.code}: #{response.body}"
      end

      body  = response.parsed_response
      batch = body['items'] || []
      break if batch.empty?

      all_items.concat(batch)

      # Check pagination flags
      page_context  = body['page_context'] || {}
      has_more_page = page_context['has_more_page']

      # Break if Zoho explicitly tells us there are no more pages,
      # or if fewer than 200 records were returned
      break if has_more_page == false || batch.size < 200

      page += 1
    end

    all_items
  end

  # ----------------------------------------------------------------------------
  # Helper: Build lookup index mapping barcode/SKU to the Zoho item hash
  # Maps SKU, EAN, and UPC if present
  # ----------------------------------------------------------------------------
  def build_item_index(zoho_items)
    index = {}

    zoho_items.each do |item|
      sku = item['sku'].to_s.strip
      index[sku] = item if sku.present?

      ean = item['ean'].to_s.strip
      index[ean] = item if ean.present?

      upc = item['upc'].to_s.strip
      index[upc] = item if upc.present?
    end

    index
  end
end
