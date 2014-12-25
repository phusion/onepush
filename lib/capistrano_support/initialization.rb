module Pomodori
  module CapistranoSupport
    def self.initialize!
      if ENV['POMODORI_PWD']
        Dir.chdir(ENV['POMODORI_PWD'])
      end

      if path = PARAMS.ssh_log
        output = File.open(path, "a")
        output.sync = true
      else
        output = STDOUT
      end
      SSHKit.config.output = SSHKit::Formatter::Pretty.new(output)

      APP_CONFIG.set_defaults!(PARAMS) if APP_CONFIG
      $current_progress = 0
    end
  end
end
