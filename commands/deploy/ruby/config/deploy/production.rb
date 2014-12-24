require 'json'
require 'uri'

CONFIG.deploy_addresses.each do |address|
  if address == "localhost"
    server(:local, :roles => ["web", "app", "db"])
  else
    uri = URI.parse("scheme://#{address}")
    hostname = uri.hostname.dup
    hostname << ":#{uri.port}" if uri.port
    server(hostname, :user => uri.user || "root", :roles => ["web", "app", "db"])
  end
end

keys = []
if CONFIG.vagrant_key
  keys << File.absolute_path(File.dirname(__FILE__) + "/../../../../../lib/vagrant_insecure_key")
end
if CONFIG.ssh_keys
  JSON.parse(CONFIG.ssh_keys).each do |filename|
    keys << filename
  end
end

set :ssh_options, { :keys => keys }
