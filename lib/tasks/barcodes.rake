# frozen_string_literal: true

# lib/tasks/barcodes.rake
#
# Purpose:
#   Backfill missing or blank barcodes for existing items in the database with their record IDs.
#
# Execution Flow:
#   STEP 1: Find all items where barcode is nil or empty string
#   STEP 2: Update each item's barcode to its database ID
#   STEP 3: Print summary of updated records

namespace :barcodes do
  desc 'Backfill missing or empty barcodes with item IDs'
  task backfill: :environment do
    # STEP 1: Find all items with blank barcodes
    items_to_update = Item.where(barcode: [nil, ''])
    total_count     = items_to_update.count

    puts "Found #{total_count} items with blank or missing barcodes."
    next if total_count.zero?

    # STEP 2: Update items with their record IDs
    updated_count = 0
    items_to_update.find_each do |item|
      item.update_column(:barcode, item.id.to_s)
      updated_count += 1
    end

    # STEP 3: Report completion summary
    puts "Successfully backfilled #{updated_count} items with their ID as barcode."
  end
end
