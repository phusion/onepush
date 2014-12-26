require_relative '../setup/params'

module Pomodori
  module Commands
    class DeployParams < Pomodori::InfrastructureConfig
      include SetupParamsLike
      SetupParamsLike.install_properties!(self)

      property :app_root, String, required: true

      # Ruby-only properties
      property :rails, BooleanValue
    end
  end
end
