task :create_app_user => :install_essentials do
  on roles(:app) do |host|
    name = CONFIG['user']

    if !test("id -u #{name} >/dev/null 2>&1")
      create_user(host, name)
    end
    case CONFIG['type']
    when 'ruby'
      case CONFIG['ruby_manager']
      when 'rvm'
        sudo(host, "usermod -a -G rvm #{name}")
      end
    end

    authorized_keys_file = sudo_capture(host, "cat /home/#{name}/.ssh/authorized_keys " +
      "2>/dev/null; true")
    authorized_keys = authorized_keys_file.split("\n", -1)
    add_pubkey_to_array(authorized_keys, "~/.ssh/id_rsa.pub")
    add_pubkey_to_array(authorized_keys, "~/.ssh/id_dsa.pub")
    if authorized_keys.join("\n").strip != authorized_keys_file.strip
      io = StringIO.new
      io.write(authorized_keys.join("\n"))
      io.rewind

      sudo(host, "mkdir -p /home/#{name}/.ssh")
      sudo_upload(host, io, "/home/#{name}/.ssh/authorized_keys")
      sudo(host, "chown #{name}: /home/#{name}/.ssh /home/#{name}/.ssh/authorized_keys && " +
        "chmod 700 /home/#{name}/.ssh && " +
        "chmod 644 /home/#{name}/.ssh/authorized_keys")
    end
  end
end

def add_pubkey_to_array(keys, path)
  path = File.expand_path(path)
  if File.exist?(path)
    File.read(path).split("\n").each do |key|
      if !keys.include?(key)
        keys << key
      end
    end
  end
end

task :create_app_dir => [:install_essentials, :create_app_user] do
  path  = CONFIG['app_dir']
  owner = CONFIG['user']

  primary_dirs     = "#{path} #{path}/releases #{path}/shared #{path}"
  flippo_repo_path = "#{path}/flippo_repo"
  repo_dirs        = "#{path}/repo #{flippo_repo_path}"

  on roles(:app) do |host|
    sudo(host, "mkdir -p #{primary_dirs} && chown #{owner}: #{primary_dirs} && chmod u=rwx,g=rx,o=x #{primary_dirs}")
    sudo(host, "mkdir -p #{path}/shared/config && chown #{owner}: #{path}/shared/config")

    sudo(host, "mkdir -p #{repo_dirs} && chown #{owner}: #{repo_dirs} && chmod u=rwx,g=,o= #{repo_dirs}")
    sudo(host, "cd #{flippo_repo_path} && if ! [[ -e HEAD ]]; then sudo -u #{owner} git init --bare; fi")

    # admin = host.user || `whoami`.strip
    # sudo(host, "mkdir -p #{repo_path} && chown #{admin}:#{owner} #{repo_path} && chmod u=rwx,g=rxs,o= #{repo_path}")
    # sudo(host, "cd #{repo_path} && if ! [[ -e HEAD ]]; then git init --bare --shared=0640 && chown -R #{admin}:#{owner} .; fi")
  end
end
