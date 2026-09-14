require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ItemLister
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # Load environment variables from .env if present
    env_file = File.expand_path('../.env', __dir__)
    if File.exist?(env_file)
      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?('#')
        key, val = line.split('=', 2)
        ENV[key.strip] ||= val.to_s.strip if key.present?
      end
    end

    config.active_job.queue_adapter = :sidekiq
  end
end
