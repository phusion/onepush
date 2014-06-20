require 'json'
require 'uri'

abort "At least one server must be specified" if !ENV['SERVERS']
JSON.parse(ENV['SERVERS']).each do |address|
  uri = URI.parse("scheme://#{address}")
  hostname = uri.hostname.dup
  hostname << ":#{uri.port}" if uri.port
  server(hostname, :user => uri.user || "root", :roles => ['app', 'db'])
end

keys = []
if ENV['VAGRANT_KEY']
  keys << File.absolute_path(File.dirname(__FILE__) + "/../../../lib/vagrant_insecure_key")
end

set :ssh_options, { :keys => keys }
