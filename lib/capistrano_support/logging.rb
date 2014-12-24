module Pomodori
  module CapistranoSupport
    # Provides logging support. This uses SSHKit's logging facilities,
    # which Capistrano also uses.
    module Logging
      def log_fatal(message)
        log_sshkit(:fatal, message)
        log_terminal(:fatal, message)
      end

      def log_error(message)
        log_sshkit(:error, message)
        log_terminal(:error, message)
      end

      def log_warn(message)
        log_sshkit(:warn, message)
        log_terminal(:warn, message)
      end

      def log_notice(message)
        log_sshkit(:info, message)
        log_terminal(:notice, message)
      end

      def log_info(message)
        log_sshkit(:info, message)
        log_terminal(:info, message)
      end

      def fatal_and_abort(message)
        log_fatal(message)
        abort
      end

      def report_progress(step, total)
        if CONFIG.report_progress?
          fraction = (step / total.to_f) * (CONFIG.progress_ceil - CONFIG.progress_base)
          $current_progress = CONFIG.progress_base + fraction
          puts "PROGRS -- #{$current_progress}"
        end
      end

    private
      def log_sshkit(level, message)
        case level
        when :fatal
          level = SSHKit::Logger::FATAL
        when :error
          level = SSHKit::Logger::ERROR
        when :warn
          level = SSHKit::Logger::WARN
        when :info
          level = SSHKit::Logger::INFO
        when :debug
          level = SSHKit::Logger::DEBUG
        when :trace
          level = SSHKit::Logger::TRACE
        else
          raise "Bug"
        end
        SSHKit.config.output << SSHKit::LogMessage.new(level, message)
      end

      def log_terminal(level, message)
        if SSHKit.config.output.original_output != STDOUT
          printf "%-6s -- %s\n", level.to_s.upcase, message
        end
      end
    end
  end
end
