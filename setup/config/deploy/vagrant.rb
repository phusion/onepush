server '127.0.0.1:5342', user: 'vagrant', roles: %w{app db}

set :ssh_options, {
  :keys => [File.absolute_path(File.dirname(__FILE__)) + "/vagrant_insecure_key"],
  :forward_agent => true
}
