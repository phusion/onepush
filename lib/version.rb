module Pomodori
  VERSION_STRING = "0.1.0"

  # Bump this version to prevent older Pomodori versions
  # from operating on this server. If you bump the major
  # version, then the user must run `pomodori migrate`.
  SETUP_VERSION  = "1.0"

  def self.semver_compatible?(our_version, their_version)
    our_major, our_minor = our_version.split(".")
    their_minor, their_minor = their_version.split(".")
    our_major == their_major && our_minor >= their_minor
  end
end
