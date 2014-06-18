address = ENV['ADDRESS']
role :app, "root@#{address}"
set :ssh_options, {
  :forward_agent => true
}
