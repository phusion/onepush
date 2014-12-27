require 'etc'
require 'fileutils'

module Pomodori
  def self.vagrant_insecure_key_path
    home = Etc.getpwuid.dir
    target_key_path = File.join(home, ".pomodori", "vagrant_insecure_key")
    if !File.exist?(target_key_path)
      orig_key_path = File.join(ROOT, "lib", "vagrant_insecure_key.key")
      FileUtils.mkdir_p(File.join(home, ".pomodori"))
      FileUtils.cp(orig_key_path, target_key_path)
      File.chmod(0600, target_key_path)
    end
    target_key_path
  end
end
