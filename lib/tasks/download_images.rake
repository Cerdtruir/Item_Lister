namespace :images do
  desc 'Download and convert images to JPG format if not already'
  task download: :environment do
    Item.all.each do |item|
      # Download the image
      downloaded_image = HTTParty.get(item.image,
                                      headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36' }).body

      # Convert to JPG
      image = MiniMagick::Image.read(downloaded_image)
      image.format 'jpg'
      image.write("public/#{item.id}.jpg")
      Cloudinary::Uploader.upload("public/#{item.id}.jpg",
                                  public_id: item.id)

    rescue StandardError => e
      puts "Error downloading image from #{item.image}: #{e.message}"
    end
  end
end
