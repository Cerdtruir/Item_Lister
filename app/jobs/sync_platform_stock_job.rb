# frozen_string_literal: true

# ==============================================================================
# SyncPlatformStockJob
#
# Background job triggered in two ways:
#   1. Automatically: Every 30 minutes via Sidekiq Cron (config/sidekiq.yml)
#   2. Manually: By the user clicking "Takealot", "WooCommerce", "Amazon", or
#      "Zoho" buttons on the inventory page (POST /items/sync_platform)
#
# COMPLETE FLOW:
#   STEP 1: Determine target platforms ('all' or specific: 'takealot'/'woocommerce'/'amazon'/'zoho')
#   STEP 2: Execute each platform's sync service sequentially:
#             - Takealot:    TakealotSyncService
#             - WooCommerce: WoocommerceSyncService
#             - Amazon:      AmazonSyncService
#             - Zoho:        ZohoSyncService
#           * Note: Failures on one platform are logged and rescued so they
#             do NOT block the other platforms from running.
#   STEP 3: Record global `last_synced_at` timestamp on all items.
# ==============================================================================
class SyncPlatformStockJob < ApplicationJob
  queue_as :default

  # Map platform names to their respective service classes
  PLATFORM_SERVICES = {
    'takealot'    => TakealotSyncService,
    'woocommerce' => WoocommerceSyncService,
    'amazon'      => AmazonSyncService,
    'zoho'        => ZohoSyncService
  }.freeze

  def perform(platform = 'all')
    target_platform = platform.to_s.downcase
    Rails.logger.info "[SyncJob] === STARTING PLATFORM SYNC: #{target_platform.upcase} ==="

    # --------------------------------------------------------------------------
    # STEP 1: Determine which platform services need to run
    # --------------------------------------------------------------------------
    services_to_run = if target_platform == 'all'
                        PLATFORM_SERVICES
                      else
                        PLATFORM_SERVICES.slice(target_platform)
                      end

    if services_to_run.empty?
      Rails.logger.warn "[SyncJob] Unknown platform: '#{target_platform}'. Nothing to sync."
      return
    end

    # --------------------------------------------------------------------------
    # STEP 2: Execute each sync service sequentially
    # --------------------------------------------------------------------------
    results = {}

    services_to_run.each do |name, service_class|
      # Check if sync service is enabled in Platform Settings (defaults to false)
      unless PlatformSetting.enabled?(name)
        Rails.logger.info "[SyncJob] -> [#{name.capitalize}] SKIPPED: Sync service is disabled in Platform Settings."
        results[name] = :disabled
        next
      end

      Rails.logger.info "[SyncJob] -> [#{name.capitalize}] Starting sync..."
      begin
        summary = service_class.new.sync
        results[name] = summary || :success
        Rails.logger.info "[SyncJob] -> [#{name.capitalize}] Finished successfully."
      rescue StandardError => e
        # Isolate errors per platform so one broken API does not abort remaining syncs
        results[name] = :failed
        Rails.logger.error "[SyncJob] -> [#{name.capitalize}] FAILED: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end
    end

    # --------------------------------------------------------------------------
    # STEP 3: Update global timestamp for the inventory dashboard
    # --------------------------------------------------------------------------
    Item.update_all(last_synced_at: Time.current)
    Rails.logger.info "[SyncJob] === PLATFORM SYNC COMPLETE (Summary: #{results.inspect}) ==="
  end
end
