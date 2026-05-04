class Item < ApplicationRecord
  validates :barcode, uniqueness: true, allow_nil: true, allow_blank: true

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
    image.write("public/#{item.id}.jpg")
    Cloudinary::Uploader.upload("public/#{item.id}.jpg",
                                public_id: item.id)
  end
end
