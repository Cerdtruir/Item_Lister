# frozen_string_literal: true

namespace :zoho do
  desc 'Exchange a one-time Zoho grant code for a permanent refresh token (usage: bin/rails zoho:token CODE=1000.xxxx)'
  task token: :environment do
    code = ENV['CODE']
    accounts_url = ENV.fetch('ZOHO_ACCOUNTS_URL', 'https://accounts.zoho.com')
    client_id = ENV.fetch('ZOHO_CLIENT_ID', '')
    client_secret = ENV.fetch('ZOHO_CLIENT_SECRET', '')

    if code.blank?
      puts 'ERROR: Please provide a grant code. Usage: bin/rails zoho:token CODE=1000.xxxx'
      exit 1
    end

    if client_id.blank? || client_secret.blank?
      puts 'ERROR: ZOHO_CLIENT_ID and ZOHO_CLIENT_SECRET must be present in .env'
      exit 1
    end

    puts "Exchanging grant code with #{accounts_url}/oauth/v2/token..."
    response = HTTParty.post(
      "#{accounts_url}/oauth/v2/token",
      headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
      body: {
        code:          code,
        grant_type:    'authorization_code',
        client_id:     client_id,
        client_secret: client_secret
      }
    )

    data = response.parsed_response
    if response.code == 200 && data['refresh_token'].present?
      puts "\n=== SUCCESS! ==="
      puts "Refresh Token: #{data['refresh_token']}"
      puts "Access Token:  #{data['access_token']}"
      puts "Expires In:    #{data['expires_in']} seconds"
      puts "\nAdd this to your .env file:"
      puts "ZOHO_REFRESH_TOKEN=#{data['refresh_token']}"
    else
      puts "\n=== FAILED (HTTP #{response.code}) ==="
      puts data.inspect
    end
  end

  desc 'Test Zoho Inventory API connection and list organizations'
  task test: :environment do
    puts 'Testing Zoho Inventory integration...'
    summary = ZohoSyncService.new.sync
    puts "Sync result: #{summary.inspect}"
  end
end
