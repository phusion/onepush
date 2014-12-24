#require_relative '../my_pretty_formatter'

module Pomodori
  module CapistranoSupport
    def self.initialize!
      if path = ENV['SSHKIT_OUTPUT']
        output = File.open(path, "a")
        output.sync = true
      else
        output = STDOUT
      end
      #SSHKit.config.output = Pomodori::MyPrettyFormatter.new(output)
    end
  end
end
