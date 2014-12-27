require 'json'
require 'uri'
require File.absolute_path(File.dirname(__FILE__) + "/../../../../../lib/vagrant_insecure_key")

PARAMS.app_server_addresses.each_with_index do |address, i|
  if address == "localhost"
    server(:local, :roles => ["app"])
  else
    uri = URI.parse("scheme://#{address}")
    hostname = uri.hostname.dup
    hostname << ":#{uri.port}" if uri.port
    server(hostname,
      :user => APP_CONFIG.user,
      :roles => ["web", "app"],
      :primary => i == 0)
  end
end

keys = []
if PARAMS.vagrant_key
  keys << Pomodori.vagrant_insecure_key_path
end
if PARAMS.ssh_keys.any?
  JSON.parse(PARAMS.ssh_keys).each do |filename|
    keys << filename
  end
end

set :ssh_options, { :keys => keys }
