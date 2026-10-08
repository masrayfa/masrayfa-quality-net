# frozen_string_literal: true

require 'rails_helper'

# Placeholder harness smoke: proves Rails boots and the test DB is reachable.
# Real rule tests land under spec/services + spec/requests (todos 13/14).
RSpec.describe 'test harness' do
  it 'boots Rails with a usable database connection' do
    expect(ActiveRecord::Base.connection.select_value('SELECT 1')).to eq(1)
  end
end
