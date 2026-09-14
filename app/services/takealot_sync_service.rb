# frozen_string_literal: true

# ==============================================================================
# TakealotSyncService
#
# Purpose:
#   Synchronize local inventory with the Takealot Seller Marketplace API.
#
# MATCHING LOGIC:
#   Takealot Seller API returns offers where `sku` corresponds to our local
#   `item.barcode`.
#
# COMPLETE EXECUTION FLOW:
#   STEP 1: Validate API credentials from ENV
#   STEP 2: Fetch all active/buyable offers from Takealot (GET /offers)
#   STEP 3: Index remote offers by SKU for fast O(1) matching: { sku => offer }
#   STEP 4: Match local items by barcode:
#             - If matched on Takealot:
#                 * listed_on_takealot = true
#                 * takealot_offer_id  = offer['offer_id']
#                 * takealot_stock     = sum of quantities in leadtime_stock
#             - If NOT on Takealot:
#                 * listed_on_takealot = false
#                 * takealot_stock     = nil
#   STEP 5: Return summary statistics ({ matched: count, total_offers: count })
# ==============================================================================
class TakealotSyncService
  BASE_URL = ENV.fetch('TAKEALOT_API_BASE_URL', 'https://marketplace-api.takealot.com/v1')
  API_KEY  = ENV.fetch('TAKEALOT_API_KEY', 'a2974de6e40b65ff36ca19a95c01da6c524b2eafd7ab6936906a0b6b5850f037fecbe5d519e0996c9ea868e201b92956f5d514eec782c1df16f421ba646dba47')

  def sync
    Rails.logger.info '[TakealotSync] =========================================='
    Rails.logger.info '[TakealotSync] STEP 1: Checking API credentials...'
    unless API_KEY.present?
      Rails.logger.warn '[TakealotSync] Skipped — TAKEALOT_API_KEY is not configured.'
      return { matched: 0, total_offers: 0, skipped: true }
    end

    # --------------------------------------------------------------------------
    # STEP 2: Fetch all active offers from Takealot API
    # --------------------------------------------------------------------------
    Rails.logger.info '[TakealotSync] STEP 2: Requesting buyable offers from Takealot API...'
    offers = fetch_all_offers
    Rails.logger.info "[TakealotSync] Received #{offers.size} offers from Takealot."

    # --------------------------------------------------------------------------
    # STEP 3: Index offers by SKU (which matches our local barcode)
    # Example offer data structure from Takealot:
    # {
    #   "offer_id" => 123456,
    #   "sku"      => "6009544507574",
    #   "leadtime_stock" => [{ "quantity" => 5, "leadtime_days" => 3 }]
    # }
    # --------------------------------------------------------------------------
    Rails.logger.info '[TakealotSync] STEP 3: Indexing Takealot offers by SKU...'
    offers_by_sku = offers.index_by { |offer| offer['sku'].to_s.strip }

    # --------------------------------------------------------------------------
    # STEP 4: Compare against local database items with barcodes
    # --------------------------------------------------------------------------
    Rails.logger.info '[TakealotSync] STEP 4: Matching local items against Takealot offers...'
    matched_count = 0
    matched_item_ids = []

    # Iterate over items that have a barcode to match against
    Item.where.not(barcode: [nil, '']).find_each do |item|
      barcode = item.barcode.to_s.strip
      offer   = offers_by_sku[barcode]

      if offer
        # Item IS listed on Takealot -> update listing flag, offer ID, and stock
        stock = extract_stock(offer)
        item.update_columns(
          listed_on_takealot: true,
          takealot_offer_id:  offer['offer_id'].to_s,
          takealot_stock:     stock
        )
        matched_item_ids << item.id
        matched_count += 1
      else
        # Item is NOT listed on Takealot -> only update if it was previously marked listed
        if item.listed_on_takealot? || item.takealot_stock.present?
          item.update_columns(listed_on_takealot: false, takealot_stock: nil)
        end
      end
    end

    # --------------------------------------------------------------------------
    # STEP 5: Return summary
    # --------------------------------------------------------------------------
    Rails.logger.info "[TakealotSync] STEP 5: Sync complete! #{matched_count} items matched on Takealot."
    Rails.logger.info '[TakealotSync] =========================================='
    { matched: matched_count, total_offers: offers.size }
  rescue StandardError => e
    Rails.logger.error "[TakealotSync] Error during sync: #{e.message}"
    raise
  end

  private

  # ----------------------------------------------------------------------------
  # Helper: Fetch all buyable offers from Takealot Seller Marketplace endpoint
  # GET /v1/offers?limit=1000&status=buyable
  # ----------------------------------------------------------------------------
  def fetch_all_offers
    response = HTTParty.get(
      "#{BASE_URL}/offers",
      query:   { limit: 1000, status: 'buyable' },
      headers: {
        'X-API-Key' => API_KEY,
        'Accept'    => 'application/json'
      },
      timeout: 30
    )

    unless response.code == 200
      raise "Takealot API returned HTTP #{response.code}: #{response.body}"
    end

    # Takealot returns payload: { "items": [ { offer_id, sku, ... } ] }
    response.parsed_response['items'] || []
  end

  # ----------------------------------------------------------------------------
  # Helper: Calculate total available stock from Takealot's `leadtime_stock`
  # Payload format:
  #   "leadtime_stock": [ { "quantity": 3, "leadtime_days": 2 }, ... ]
  # ----------------------------------------------------------------------------
  def extract_stock(offer)
    stock_list = offer['leadtime_stock']
    return nil unless stock_list.is_a?(Array)

    # Sum all quantities across warehouses / lead times
    stock_list.sum { |slot| slot['quantity'].to_i }
  end
end
