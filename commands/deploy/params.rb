require_relative '../setup/params'

module Pomodori
  module Commands
    class DeployParams < SetupParams
      property :app_root, String, required: true

      # Ruby-only properties
      property :bundler, BooleanValue
      property :rails, BooleanValue
    end
  end
end
