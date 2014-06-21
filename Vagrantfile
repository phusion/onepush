VAGRANTFILE_API_VERSION = "2"
ONEPUSH_SSH_HOST_PORT = 5342

case ENV['VM_OS']
when "ubuntu14", nil
  BOX_NAME   = "phusion-open-ubuntu-14.04-amd64"
  BOX_URL    = "https://oss-binaries.phusionpassenger.com/vagrant/boxes/latest/ubuntu-14.04-amd64-vbox.box"
  VF_BOX_URL = "https://oss-binaries.phusionpassenger.com/vagrant/boxes/latest/ubuntu-14.04-amd64-vmwarefusion.box"
when "ubuntu12"
  BOX_NAME   = "phusion-open-ubuntu-12.04-amd64"
  BOX_URL    = "https://oss-binaries.phusionpassenger.com/vagrant/boxes/latest/ubuntu-12.04-amd64-vbox.box"
  VF_BOX_URL = "https://oss-binaries.phusionpassenger.com/vagrant/boxes/latest/ubuntu-12.04-amd64-vmwarefusion.box"
when "centos"
  BOX_NAME   = "centos-6.4-x86_64"
  BOX_URL    = "http://developer.nrel.gov/downloads/vagrant-boxes/CentOS-6.4-x86_64-v20130731.box"
  VF_BOX_URL = "https://dl.dropbox.com/u/5721940/vagrant-boxes/vagrant-centos-6.4-x86_64-vmware_fusion.box"
else
  abort "Invalid VM OS"
end

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = BOX_NAME
  config.vm.box_url = BOX_URL
  config.vm.network :forwarded_port, :guest => 22, :host => ONEPUSH_SSH_HOST_PORT

  config.vm.provider :vmware_fusion do |f, override|
    override.vm.box_url = VF_BOX_URL
  end
end
