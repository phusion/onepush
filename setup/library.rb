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

def fatal(message)
  log_sshkit(:fatal, message)
end

def notice(message)
  log_sshkit(:info, message)
end

def info(message)
  log_sshkit(:info, message)
end

def check_config_requirements(config)
  # TODO
end

def fatal_and_abort(message)
  fatal(message)
  abort
end
