# frozen_string_literal: true

# Configure Sidekiq and sidekiq-cron scheduled jobs.
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }

  # Load cron schedule from config/sidekiq.yml
  schedule_file = Rails.root.join('config', 'sidekiq.yml')
  if File.exist?(schedule_file)
    schedule = YAML.load_file(schedule_file)[:schedule]
    Sidekiq::Cron::Job.load_from_hash(schedule) if schedule
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end
