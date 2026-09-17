class Item < ApplicationRecord
  # Callbacks to manage fallback barcode assignment
  before_validation :normalize_blank_barcode
  before_save :assign_id_if_persisted, if: -> { barcode.blank? && id.present? }
  after_create :set_id_as_barcode, if: -> { barcode.blank? }

  validates :barcode, uniqueness: true, allow_nil: true

  CATEGORIES = [
    'Baby & Toddler',
    'Beauty & Personal Care',
    'Books & Stationery',
    'Clothing, Shoes & Accessories',
    'Computers & Electronics',
    'DIY, Automotive & Industrial',
    'Gaming',
    'Garden, Pool & Patio',
    'Health & Household',
    'Home & Kitchen',
    'Liquor',
    'Luggage & Travel',
    'Mobile & Wearables',
    'Music, Movies & TV',
    'Musical Instruments',
    'Pets',
    'Sport & Training',
    'Toys',
    'TV, Audio & Video'
  ].freeze

  CONDITIONS = [
    'Brand New',
    'New Unsealed',
    'Used'
  ].freeze

  # Virtual attribute to accept direct image file uploads from forms
  attr_accessor :image_file

  # ============================================================================
  # Purpose: Downloads a remote image URL, converts to JPG with a white
  #          background, and uploads it to Cloudinary with public_id = item.id.
  #
  # Execution Flow:
  #   STEP 1: Validate presence and format of image URL
  #   STEP 2: Ensure local public/assets directory exists
  #   STEP 3: Download remote image via HTTParty using browser User-Agent
  #   STEP 4: Process image with MiniMagick (flatten transparency against white, format JPG)
  #   STEP 5: Save processed JPG to public/assets/#{item.id}.jpg
  #   STEP 6: Upload saved JPG to Cloudinary under public_id: item.id
  # ============================================================================
  def upload_image(target_item = self, force: false)
    target = target_item || self
    return unless target.image.present?
    return unless target.image.to_s.start_with?('http://', 'https://')

    local_path = "public/assets/#{target.id}.jpg"
    return if !force && File.exist?(local_path)

    # STEP 1: Ensure destination directory exists
    FileUtils.mkdir_p('public/assets')

    # STEP 2: Download the image
    downloaded_image = HTTParty.get(
      target.image,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36'
      },
      timeout: 10
    ).body

    return if downloaded_image.blank?

    # STEP 3: Process image with MiniMagick
    img = MiniMagick::Image.read(downloaded_image)
    img.combine_options do |c|
      c.background 'white'
      c.flatten
    end
    img.format 'jpg'

    # STEP 4: Write to local assets
    img.write(local_path)

    # STEP 5: Upload to Cloudinary
    Cloudinary::Uploader.upload(local_path, public_id: target.id)
  rescue StandardError => e
    Rails.logger.error("Failed to upload image to Cloudinary for Item ##{target&.id}: #{e.message}")
    false
  end

  # ============================================================================
  # Purpose: Processes a locally uploaded file, converts to JPG with a white
  #          background, and uploads it to Cloudinary with public_id = item.id.
  #
  # Execution Flow:
  #   STEP 1: Validate uploaded file input
  #   STEP 2: Ensure local public/assets directory exists
  #   STEP 3: Process image with MiniMagick (flatten transparency against white, format JPG)
  #   STEP 4: Save processed JPG to public/assets/#{id}.jpg
  #   STEP 5: Upload saved JPG to Cloudinary under public_id: id
  #   STEP 6: Set image column to Cloudinary URL if blank
  # ============================================================================
  def upload_image_file(file)
    return unless file.present?

    # STEP 1: Ensure destination directory exists
    FileUtils.mkdir_p('public/assets')
    local_path = "public/assets/#{id}.jpg"

    # STEP 2: Process image file with MiniMagick
    file_path = file.respond_to?(:path) ? file.path : file.to_s
    img = MiniMagick::Image.open(file_path)
    img.combine_options do |c|
      c.background 'white'
      c.flatten
    end
    img.format 'jpg'

    # STEP 3: Write processed image to local storage
    img.write(local_path)

    # STEP 4: Upload to Cloudinary
    Cloudinary::Uploader.upload(local_path, public_id: id)

    # STEP 5: Update image URL column if blank
    cloudinary_url = "https://res.cloudinary.com/dwi7jdore/image/upload/#{id}.jpg"
    update_column(:image, cloudinary_url) if image.blank?
    true
  rescue StandardError => e
    Rails.logger.error("Failed to upload image file to Cloudinary for Item ##{id}: #{e.message}")
    false
  end

  # ============================================================================
  # Purpose: Unified entrypoint to upload image to Cloudinary from either an
  #          uploaded file or an existing image URL.
  #
  # Execution Flow:
  #   STEP 1: If file is provided, process and upload file
  #   STEP 2: Else if image URL is present, download and upload from URL
  # ============================================================================
  def upload_to_cloudinary(file: nil)
    # STEP 1: Process file upload if provided
    if file.present?
      upload_image_file(file)
    # STEP 2: Process image URL if present
    elsif image.present?
      upload_image(self, force: true)
    end
  end

  # ============================================================================
  # Purpose: Forces re-download and re-upload of the current item's image URL.
  # ============================================================================
  def force_upload_image
    return unless image.present?
    return unless image.to_s.start_with?('http://', 'https://')

    # STEP 1: Ensure destination directory exists
    FileUtils.mkdir_p('public/assets')
    local_path = "public/assets/#{id}.jpg"

    # STEP 2: Download image with User-Agent header
    downloaded_image = HTTParty.get(
      image,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36'
      },
      timeout: 10
    ).body

    return if downloaded_image.blank?

    # STEP 3: Process with MiniMagick
    img = MiniMagick::Image.read(downloaded_image)
    img.combine_options do |c|
      c.background 'white'
      c.flatten
    end
    img.format 'jpg'

    # STEP 4: Write to local assets
    img.write(local_path)

    # STEP 5: Upload to Cloudinary
    Cloudinary::Uploader.upload(local_path, public_id: id)
  end

  private

  # STEP 1: Normalize blank barcode strings (e.g., "" submitted from forms) to nil
  # This prevents PostgreSQL unique index violations ("Key (barcode)=() already exists")
  def normalize_blank_barcode
    self.barcode = barcode.presence
  end

  # STEP 2: If an existing persisted record has its barcode cleared, default to its ID
  def assign_id_if_persisted
    self.barcode = id.to_s
  end

  # STEP 3: For newly created records without a barcode, assign the database ID as barcode
  def set_id_as_barcode
    update_column(:barcode, id.to_s)
    self.barcode = id.to_s
  end
end
