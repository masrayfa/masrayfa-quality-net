# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'
# Test-only boot defaults; real environments always set their own values.
ENV['SECRET_KEY_BASE'] ||= 'test-secret-key-base'
ENV['ALLOWED_ORIGINS'] ||= '*'

require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |file| require file }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # database_cleaner (spec/support/database_cleaner.rb) owns cleaning.
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
