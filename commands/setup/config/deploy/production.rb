require 'json'
require 'uri'
require File.absolute_path(File.dirname(__FILE__) + "/../../../../lib/vagrant_insecure_key")

PARAMS.app_server_addresses.each_with_index do |address, i|
  if address == "localhost"
    server(:local, :roles => ["app"])
  else
    uri = URI.parse("scheme://#{address}")

    hostname = uri.hostname.dup
    hostname << ":#{uri.port}" if uri.port

    roles = ["app"]
    if address == PARAMS.db_server_address
      roles << "db"
    end

    server(hostname,
      :user => uri.user || "root",
      :roles => roles,
      :primary => i == 0)
  end
end

if PARAMS.db_server_address && !PARAMS.app_server_addresses.include?(PARAMS.db_server_address)
  if PARAMS.db_server_address == "localhost"
    server(:local, :roles => ["db"])
  else
    uri = URI.parse("scheme://#{PARAMS.db_server_address}")
    hostname = uri.hostname.dup
    hostname << ":#{uri.port}" if uri.port
    server(hostname, :user => uri.user || "root", :roles => ["db"])
  end
end

keys = []
if PARAMS.vagrant_key
  keys << Pomodori.vagrant_insecure_key_path
end
PARAMS.ssh_keys.each do |filename|
  keys << filename
end

set :ssh_options, { :keys => keys }
