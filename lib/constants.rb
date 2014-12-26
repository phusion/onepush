module Pomodori
  VERSION_STRING = "0.1.0"

  # Bump this version to prevent older Pomodori versions
  # from operating on this server. If you bump the major
  # version, then the user must run `pomodori migrate`.
  SETUP_VERSION  = "1.0"

  DEFAULT_RUBY_VERSION = "2.1.5"

  POMODORI_APP_NAME = ENV["POMODORI_APP_NAME"] || "Pomodori"

  def self.setup_version_compatible?(their_version)
    our_major, our_minor = SETUP_VERSION.split(".")
    their_major, their_minor = their_version.split(".")
    our_major == their_major && our_minor >= their_minor
  end

  def self.setup_version_migratable?(their_version)
    our_major, our_minor = SETUP_VERSION.split(".")
    their_major, their_minor = their_version.split(".")
    (our_major == their_major && our_minor >= their_minor) ||
      (our_major > their_major)
  end
end
