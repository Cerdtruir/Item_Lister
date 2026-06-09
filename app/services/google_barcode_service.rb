class GoogleBarcodeService
  def initialize(barcode)
    @barcode = barcode
  end

  def fetch_item_data
    # 1. Try Google Search Web & Images
    data = fetch_from_google

    # 2. If still blank, provide a clean default structure
    data[:name] = "Product #{@barcode}" if data[:name].blank?
    data[:description] = 'No description found. Please fill in details.' if data[:description].blank?
    data[:category] = 'General' if data[:category].blank?
    data[:selling_price] = 0.0
    data[:original_price] = 0.0

    data
  rescue StandardError => e
    Rails.logger.error("GoogleBarcodeService Error: #{e.message}\n#{e.backtrace.join("\n")}")
    {
      name: "Product #{@barcode}",
      description: "Error occurred during lookup: #{e.message}",
      category: 'General',
      selling_price: 0.0,
      original_price: 0.0,
      barcode: @barcode
    }
  end

  private

  def fetch_from_google
    # We will search with a desktop Chrome user agent and gbv=1 parameter
    web_url = "https://www.google.com/search?q=#{CGI.escape(@barcode)}&hl=en&gbv=1"
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'
    }

    name = nil
    description = nil
    image = nil

    begin
      # Fetch Google search
      web_res = HTTParty.get(web_url, headers: headers, timeout: 5)
      # If we got a JS redirect/challenge page (e.g. contains 'enablejs' or redirect script), it means we are blocked
      if (web_res.code == 200) && !(web_res.body.include?('enablejs') || web_res.body.include?('Please click here if you are not redirected'))
        doc = Nokogiri::HTML(web_res.body)

        # In classic non-JS desktop Google search, titles are h3 tags
        h3s = doc.css('h3')
        if h3s.any?
          # Clean up the title (remove common barcode/retail suffixes)
          first_title = h3s.first.text.strip
          name = clean_product_name(first_title)

          # Extract description snippet
          parent = h3s.first.parent
          5.times do
            break if parent.nil? || parent.name == 'div'

            parent = parent.parent
          end
          if parent
            text_blocks = parent.css('div, span, p').map(&:text).select do |t|
              t.length > 30 && !t.include?(first_title)
            end
            description = text_blocks.first.strip if text_blocks.any?
          end
        end
      end
    rescue StandardError => e
      Rails.logger.warn("Google Web Search query failed: #{e.message}")
    end

    begin
      # Fetch Google Images
      img_url = "https://www.google.com/search?q=#{CGI.escape(@barcode)}&tbm=isch&hl=en&gbv=1"
      img_res = HTTParty.get(img_url, headers: headers, timeout: 5)
      if img_res.code == 200 && !img_res.body.include?('enablejs')
        img_doc = Nokogiri::HTML(img_res.body)

        # Look for images from Google's image CDN
        images = []
        img_doc.css('img').each do |img|
          src = img['src'] || img['data-src']
          next unless src
          next if src.include?('logo') || src.include?('gif')

          images << src if src.include?('gstatic.com') || src.start_with?('http')
        end
        image = images.first if images.any?
      end
    rescue StandardError => e
      Rails.logger.warn("Google Image Search query failed: #{e.message}")
    end

    {
      name: name,
      description: description,
      image: image,
      barcode: @barcode
    }
  end

  def clean_product_name(title)
    title = title.gsub(/\s*-\s*Barcode\s*Lookup/i, '')
    title = title.gsub(/\s*-\s*UPCitemdb/i, '')
    title = title.gsub(/\s*-\s*Amazon\.com/i, '')
    title = title.gsub(/\s*-\s*eBay/i, '')
    title = title.gsub(/\s*\|\s*Buycott/i, '')
    title.strip
  end
end
