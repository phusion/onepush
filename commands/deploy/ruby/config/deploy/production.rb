require 'json'
require 'uri'

PARAMS.app_server_addresses.each_with_index do |address, i|
  if address == "localhost"
    server(:local, :roles => ["app"])
  else
    uri = URI.parse("scheme://#{address}")
    hostname = uri.hostname.dup
    hostname << ":#{uri.port}" if uri.port
    server(hostname,
      :user => uri.user || "root",
      :roles => ["web", "app"],
      :primary => i == 0)
  end
end

keys = []
if PARAMS.vagrant_key
  keys << File.absolute_path(File.dirname(__FILE__) + "/../../../../lib/vagrant_insecure_key")
end
if PARAMS.ssh_keys.any?
  JSON.parse(PARAMS.ssh_keys).each do |filename|
    keys << filename
  end
end

set :ssh_options, { :keys => keys }
