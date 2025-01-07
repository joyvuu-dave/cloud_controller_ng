namespace :db do
  desc 'Load usage event seed data'
  task load_usage_events: :environment do
    $LOAD_PATH.unshift(File.expand_path('../../spec', __dir__))

    ENV['DB'] = 'mysql'
    ENV['DB_CONNECTION_STRING'] = 'mysql2://root:supersecret@127.0.0.1:3306/ccdb'

    require 'machinist/sequel'
    require 'machinist/object'
    require 'support/bootstrap/spec_bootstrap'

    # Initialize the test environment
    VCAP::CloudController::SpecBootstrap.init

    require File.expand_path('../../db/seeds/usage_events', __dir__)
    puts 'Created seed usage events'
  end
end
