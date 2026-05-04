class TakealotBarcodeService
  BASE_URL = 'https://www.takealot.com'.freeze

  def initialize(barcode)
    @barcode = barcode
    @search_url = "#{BASE_URL}/all?qsearch=#{barcode}"
  end

  def fetch_item_data
    product_url = find_product_url
    return { error: 'Product not found on Takealot for this barcode.' } unless product_url

    TakealotService.new(product_url, @barcode).fetch_data
  end

  def find_product_url
    url = URI("https://api.takealot.com/rest/v-1-16-0/searches/products,filters,facets,sort_options,breadcrumbs,slots_audience,context,seo,layout?qsearch=#{@barcode}")

    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true

    request = Net::HTTP::Get.new(url)
    request['accept'] = '*/*'
    request['accept-language'] = 'en-GB,en;q=0.6'
    request['cache-control'] = 'max-age=0'
    request['dnt'] = '1'
    request['origin'] = 'https://www.takealot.com'
    request['priority'] = 'u=1, i'
    request['referer'] = 'https://www.takealot.com/'
    request['sec-ch-ua'] = '"Chromium";v="142", "Brave";v="142", "Not_A Brand";v="99"'
    request['sec-ch-ua-mobile'] = '?0'
    request['sec-ch-ua-platform'] = '"Windows"'
    request['sec-fetch-dest'] = 'empty'
    request['sec-fetch-mode'] = 'cors'
    request['sec-fetch-site'] = 'same-site'
    request['sec-gpc'] = '1'
    request['user-agent'] =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36'

    response = https.request(request)

    return nil unless response.code == '200'

    json = JSON.parse(response.body)
    results = json.dig('sections', 'products', 'results')
    return nil if results.nil? || results.empty?

    "#{BASE_URL}/X/PLID#{results[0]['product_views']['core']['id']}"
  end
end
