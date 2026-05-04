class TakealotService
  def initialize(takealot_link, barcode = nil)
    @takealot_link = takealot_link
  end

  def fetch_data(url = @takealot_link, barcode = nil)
    plid = url[/PLID\d+/].split('=').first
    params = url.split('?').last
    key, value = params.split('=')
    params = {
      key.to_sym => value
    }
    product = get_item_data(plid, params)
    product = JSON.parse(product.body)
    description = ActionController::Base.helpers.strip_tags(product['description']['html'])
    image = product['gallery']['images'][0].gsub('{size}', 'zoom')
    barcode = product['flixmedia']['ean']
    category = product['data_layer']['departmentname']
    selling_price = product&.[]('buybox')&.[]('items')&.[](0)&.[]('price')
    selling_price = selling_price*0.93 - 40
    selling_price = selling_price.round(0) - 0.05
    
    {
      name: product['core']['title'], description:,
      category:, original_price: product&.[]('buybox')&.[]('items')&.[](0)&.[]('listing_price'),
      selling_price:, image:, takealot_url: @takealot_link, barcode: barcode
    }
  end

  def get_item_data(plid, params)
    uri = URI("https://api.takealot.com/rest/v-1-12-0/product-details/#{plid}")
    uri.query = URI.encode_www_form(params)

    req = Net::HTTP::Get.new(uri)
    req['accept'] = '*/*'
    req['accept-language'] = 'en-GB,en;q=0.8'
    req['cache-control'] = 'max-age=0'
    req['dnt'] = '1'
    req['origin'] = 'https://www.takealot.com'
    req['priority'] = 'u=1, i'
    req['referer'] = 'https://www.takealot.com/'
    req['sec-ch-ua'] = '"Not)A;Brand";v="99", "Brave";v="127", "Chromium";v="127"'
    req['sec-ch-ua-mobile'] = '?0'
    req['sec-ch-ua-platform'] = '"Linux"'
    req['sec-fetch-dest'] = 'empty'
    req['sec-fetch-mode'] = 'cors'
    req['sec-fetch-site'] = 'same-site'
    req['sec-gpc'] = '1'
    req['user-agent'] =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36'

    req_options = {
      use_ssl: uri.scheme == 'https'
    }
    Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(req)
    end
  end
end
