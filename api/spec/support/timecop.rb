# frozen_string_literal: true

RSpec.configure do |config|
  config.after(:each) { Timecop.return }
end
