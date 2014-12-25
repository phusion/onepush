require_relative '../setup/params'

module Pomodori
  module Commands
    class DeployParams < SetupParams
      property :app_root, required: true
      property :deploy_addresses, Array[String], required: true
    end
  end
end
