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

  def upload_image(item)
    return if File.exist?("public/#{item.id}.jpg")

    # Download the image
    downloaded_image = HTTParty.get(item.image,
                                    headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36' }).body
    image = MiniMagick::Image.read(downloaded_image)

    # Flatten against a white background if there's transparency
    image.combine_options do |c|
      c.background 'white'
      c.flatten
    end

    # Convert to JPG
    image.format 'jpg'
    image.write("public/assets/#{item.id}.jpg")
    Cloudinary::Uploader.upload("public/assets/#{item.id}.jpg",
                                public_id: item.id)
  end

  def force_upload_image
    return unless image.present?

    downloaded_image = HTTParty.get(image,
                                    headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36' }).body
    img = MiniMagick::Image.read(downloaded_image)

    img.combine_options do |c|
      c.background 'white'
      c.flatten
    end

    img.format 'jpg'
    img.write("public/assets/#{id}.jpg")
    Cloudinary::Uploader.upload("public/assets/#{id}.jpg",
                                public_id: id)
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
