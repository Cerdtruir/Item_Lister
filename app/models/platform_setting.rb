# frozen_string_literal: true

# ==============================================================================
# PlatformSetting
#
# Purpose:
#   Manages per-platform sync service enablement (Takealot, WooCommerce, Amazon, Zoho).
#   Provides class-level helpers to check if a service is enabled and toggle its state.
#   All platform sync services default to DISABLED (false) per system requirements.
#
# PLATFORMS MANAGED:
#   - 'takealot'
#   - 'woocommerce'
#   - 'amazon'
#   - 'zoho'
# ==============================================================================
class PlatformSetting < ApplicationRecord
  VALID_PLATFORMS = %w[takealot woocommerce amazon zoho].freeze

  validates :name, presence: true, uniqueness: true, inclusion: { in: VALID_PLATFORMS }

  # STEP 1: Check if a given platform sync service is enabled (defaults to false)
  def self.enabled?(platform_name)
    platform = platform_name.to_s.downcase.strip
    return false unless VALID_PLATFORMS.include?(platform)

    setting = find_by(name: platform)
    setting ? setting.enabled? : false
  end

  # STEP 2: Toggle the enabled status of a platform sync service
  def self.toggle!(platform_name)
    platform = platform_name.to_s.downcase.strip
    return false unless VALID_PLATFORMS.include?(platform)

    setting = find_or_initialize_by(name: platform)
    setting.enabled = !setting.enabled
    setting.save!
    setting.enabled?
  end

  # STEP 3: Return a hash of all platform statuses: { 'takealot' => false, 'woocommerce' => false, ... }
  def self.all_statuses
    existing = where(name: VALID_PLATFORMS).index_by(&:name)

    VALID_PLATFORMS.each_with_object({}) do |platform, hash|
      hash[platform] = existing[platform] ? existing[platform].enabled? : false
    end
  end
end
