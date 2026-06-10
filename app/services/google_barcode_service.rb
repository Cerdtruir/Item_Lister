class GoogleBarcodeService
  def initialize(barcode)
    @barcode = barcode
  end

  def fetch_item_data
    # Step 1: Try UPC Item DB
    data = fetch_from_upc_item_db
    return data if data && data[:name].present? && !data[:name].start_with?('Product')

    # Step 2: Try Google Search (or fallback to DuckDuckGo if Google is blocked)
    data = fetch_from_search_engines
    return data if data && data[:name].present? && !data[:name].start_with?('Product')

    # Step 3: Final fallback structure
    {
      name: "Product #{@barcode}",
      description: 'No description found. Please fill in details.',
      category: 'General',
      selling_price: 0.0,
      original_price: 0.0,
      barcode: @barcode,
      image: nil
    }
  rescue StandardError => e
    Rails.logger.error("GoogleBarcodeService Error: #{e.message}\n#{e.backtrace.join("\n")}")
    {
      name: "Product #{@barcode}",
      description: "Error occurred during lookup: #{e.message}",
      category: 'General',
      selling_price: 0.0,
      original_price: 0.0,
      barcode: @barcode,
      image: nil
    }
  end

  private

  def fetch_from_upc_item_db
    url = "https://api.upcitemdb.com/prod/trial/lookup?upc=#{CGI.escape(@barcode)}"
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'
    }
    res = HTTParty.get(url, headers: headers, timeout: 5)
    return nil unless res.code == 200

    parsed = JSON.parse(res.body)
    return nil unless parsed['items'] && parsed['items'].any?

    item = parsed['items'].first

    {
      name: item['title'],
      description: item['description'],
      image: item['images']&.first,
      barcode: @barcode
    }
  rescue StandardError => e
    Rails.logger.warn("UPC Item DB lookup failed: #{e.message}")
    nil
  end

  def fetch_from_search_engines
    # Try Google Search first
    data = fetch_from_google
    return data if data[:name].present?

    # Fallback to DuckDuckGo HTML Search
    fetch_from_duckduckgo
  end

  def fetch_from_google
    web_url = "https://www.google.com/search?q=#{CGI.escape(@barcode)}&hl=en&gbv=1"
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'
    }

    name = nil
    description = nil
    image = nil

    begin
      web_res = HTTParty.get(web_url, headers: headers, timeout: 5)
      if web_res.code == 200 && !web_res.body.include?('enablejs') && !web_res.body.include?('Please click here')
        doc = Nokogiri::HTML(web_res.body)
        h3s = doc.css('h3')
        if h3s.any?
          first_title = h3s.first.text.strip
          name = clean_product_name(first_title)

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
      img_url = "https://www.google.com/search?q=#{CGI.escape(@barcode)}&tbm=isch&hl=en&gbv=1"
      img_res = HTTParty.get(img_url, headers: headers, timeout: 5)
      if img_res.code == 200 && !img_res.body.include?('enablejs')
        img_doc = Nokogiri::HTML(img_res.body)
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

  def fetch_from_duckduckgo
    url = "https://html.duckduckgo.com/html/?q=#{CGI.escape(@barcode)}"
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'
    }
    res = HTTParty.get(url, headers: headers, timeout: 5)
    return nil unless res.code == 200

    doc = Nokogiri::HTML(res.body)
    results = doc.css('.result')
    return nil if results.empty?

    first_result = nil
    results.each do |r|
      title = r.css('.result__title').text.strip
      next if title.include?('No results found')

      first_result = r
      break
    end
    return nil unless first_result

    title = first_result.css('.result__title').text.strip
    name = clean_product_name(title)
    description = first_result.css('.result__snippet')&.text&.strip

    {
      name: name,
      description: description,
      image: nil,
      barcode: @barcode,
      category: 'General',
      selling_price: 0.0,
      original_price: 0.0
    }
  rescue StandardError => e
    Rails.logger.warn("DuckDuckGo lookup failed: #{e.message}")
    nil
  end

  def clean_product_name(title)
    title = title.gsub(/\s*-\s*Barcode\s*Lookup/i, '')
    title = title.gsub(/\s*-\s*UPCitemdb/i, '')
    title = title.gsub(/\s*-\s*Amazon\.com/i, '')
    title = title.gsub(/\s*-\s*eBay/i, '')
    title = title.gsub(/\s*\|\s*Buycott/i, '')
    title = title.gsub(/\s*-\s*Amazon/i, '')
    title.strip
  end
end
