class BobshopJob < ApplicationJob
  queue_as :default

  def perform
    items = Item.all
    headers = [
      'Listing Type [mandatory]',
      'TITLE [Text Title for Item - Max 100 chars]',
      'Primary Category [mandatory Number]',
      'Secondary Category [optional Number - incurs a fee]',
      'Location [optional Specify location country of the product]',
      'Traders Reference [optional Max 100 chars]',
      'Start Date/Time [mandatory Date dd/mm/yyyy HH:mm]',
      'Stop Date/Time [mandatory Date dd/mm/yyyy HH:mm]',
      'Number of Items [mandatory Number]',
      'Number of Items Per Lot [optional Number]',
      'Auction Starting Bid Amount [mandatory for auctions Currency 0.00]',
      'Auction Bid Increment [mandatory for auctions - specify an amount in decimal format. Currency 0.00]',
      'Auction Reserve Amount [optional only for auctions Currency 0.00]',
      'Buy Now Price (Fixed Price) [mandatory field for Buy Now items Currency 0.00]',
      'Recommended Retail Price [optional Currency 0.00]',
      'Allow Offers yes or',
      'Currency [mandatory R for ZAR]',
      'Item Condition [mandatory] NEW or SECOND_HAND or REFURBISHED',
      "Image URLs [Optional but recommended. Separate multiple URLs with colon ':']",
      'Auto Re-list Options [optional] RELIST_DAILY or RELIST_IMMEDIATELY or RELIST_DAILY_ALL or RELIST_IMMEDIATELY_ALL',
      'Number of Auto Relists [optional Number] The number of times to relist - if relisting is specified by the previous column',
      'Item Description [optional but recommended Max 8000 chars] Text or html description of the item for sale. html descriptions can provide attractive and sophisticated descriptions including additional images using html tags such as <img src=http://www.somedomain.com/images/item1.gif>',
      'Discreet Listing [optional] yes or',
      'Home Page Featured Listing [optional - Incurs a Fee] yes or',
      'Category Page Featured Listing [optional - Incurs a Fee] yes or',
      'Priority Listing [optional - Incurs a Fee] yes or',
      'Highlighted Listing [optional - Incurs a Fee] yes or',
      'Bold Title Listing [optional - Incurs a Fee] yes or',
      'Promotional Listing [optional - Incurs a Fee] yes or',
      'Premium Listings [optional - Incurs a Fee]yes or',
      'Copy Enhancements if Relisting [optional] yes or',
      'Warranty Type [optional] or NOT_OFFERED or REPLACEMENT or DEALER or MANUFACTURER',
      'Warranty Remarks [optional Max 300 chars]',
      'Guarantee Type [optional] or MONEY_BACK_7_DAYS or MONEY_BACK_10_DAYS or MONEY_BACK_15_DAYS or MONEY_BACK_30_DAYS or REPLACEMENT_7_DAYS or REPLACEMENT_10_DAYS or REPLACEMENT_15_DAYS or REPLACEMENT_30_DAYS',
      'Guarantee Remarks [optional Max 300 chars]',
      'Prompts [optional]',
      'Shipping Option [optional]',
      'Automatic Extension Minutes [not available for most users blank or the number 1]',
      'Global Trade Item Number(GTIN) [optional] GTIN or',
      'Width [optional in cm]',
      'Length [optional in cm]',
      'Height [optional in cm]',
      'Weight [optional in kg]',
      "End of Record [mandatory] set to 'End'"
    ]

    CSV.open('public/bobshop_items.csv', 'w', write_headers: true, headers:) do |writer|
      items.each do |item|
        next if item.quantity.zero?

        selling_price = (item.selling_price * 1.07).round(2)
        selling_price += 30 if selling_price < 300
        category_id = get_category_id(item.name)

        description = "#{item.description}"
        description += "\n\nView my bobshop reviews and items at: https://www.bobshop.co.za/user/1475301/The_Deal_Site"

        condition = if item.condition.include?('Demo')
                      'SECOND_HAND'
                    else
                      'NEW'
                    end

        writer << [
          'FIXED_PRICE',
          "#{item.name} - #{item.condition}",
          category_id,
          '',
          'South Africa',
          '',
          Time.now.strftime('%d/%m/%Y %H:%M'),
          (Time.now + 30.days).strftime('%d/%m/%Y %H:%M'),
          item.quantity,
          '',
          '',
          '',
          '',
          selling_price,
          '',
          'yes',
          'R',
          condition,
          "https://res.cloudinary.com/dwi7jdore/image/upload/#{item.id}.jpg",
          'RELIST_IMMEDIATELY',
          '20',
          description,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          'MONEY_BACK_7_DAYS',
          'We stand by this guarantee',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          'End'
        ]
        sleep 0.5
      end
    end
  end

  def get_category_id(name)
    name = CGI.escape(name)

    url = URI("https://www.bobshop.co.za/mobilejquery/jsp/bobapi/BobApiCategorySuggestionsAJAXHandler.jsp?searchText=#{name}")

    https = Net::HTTP.new(url.host, url.port)
    https.use_ssl = true

    request = Net::HTTP::Get.new(url)
    request['authority'] = 'www.bobshop.co.za'
    request['accept'] = '*/*'
    request['accept-language'] = 'en-GB,en;q=0.6'
    request['dnt'] = '1'
    request['referer'] = 'https://www.bobshop.co.za/'
    request['sec-ch-ua'] = '"Chromium";v="122", "Not(A:Brand";v="24", "Brave";v="122"'
    request['sec-ch-ua-mobile'] = '?0'
    request['sec-ch-ua-platform'] = '"Linux"'
    request['sec-fetch-dest'] = 'empty'
    request['sec-fetch-mode'] = 'cors'
    request['sec-fetch-site'] = 'same-origin'
    request['sec-gpc'] = '1'
    request['user-agent'] =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    request['x-requested-with'] = 'XMLHttpRequest'

    response = https.request(request)
    json = JSON.parse(response.body)
    json.first['categoryId']
  rescue StandardError => e
    p "Error getting category id for #{name} - #{e.message}"
    retry
  end
end
