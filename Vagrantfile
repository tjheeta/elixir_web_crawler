$boxes = [
  {
    :name => :storage1,
    :group => "storage"
    #:forwards => { 80 => 1080, 443 => 1443 }
  },
  {
    :name => :worker1,
    :group => "worker",
  },
  {
    :name => :worker2,
    :group => "worker",
  }
]
lxc_snapshot_suffix = "none"

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  config.vm.provider :virtualbox do |vb, override|
    override.vm.box = "ubuntu/trusty64"
    override.vm.box_url = "https://vagrantcloud.com/ubuntu/boxes/trusty64/versions/14.04/providers/virtualbox.box"
  end
  config.vm.provider :lxc do |lxc, override|
    override.vm.box = "trusty64-lxc"
    override.vm.box_url = "https://vagrantcloud.com/fgrehm/boxes/trusty64-lxc/versions/2/providers/lxc.box"
    lxc.backingstore = "btrfs"
    lxc.snapshot_suffix = lxc_snapshot_suffix
  end
  $groups = { "all" => [] }
  $boxes.each do | opts |
    if ! $groups.has_key?(opts[:group])
      $groups[opts[:group]] = [ opts[:name] ]
    else
      $groups[opts[:group]].push(opts[:name])
    end
    $groups["all"].push(opts[:name])
  end

  $boxes.each_with_index do | opts, index |
     config.vm.define(opts[:name]) do |config|
       config.vm.hostname =   "%s" % [ opts[:name].to_s ] 
       opts[:forwards].each do |guest_port,host_port|
         config.vm.network :forwarded_port, guest: guest_port, host: host_port
       end if opts[:forwards]

       # configure with ansible
       if index == $boxes.size - 1 
         config.vm.provision :ansible do |ansible|
           #ansible.verbose = "vvvv"
           ansible.playbook = "ansible/playbook.yml"
           ansible.groups = $groups
           ansible.sudo = true
           ansible.limit = "all"
           ansible.extra_vars = { ansible_ssh_user: 'vagrant' }
         end
       end
     end if ! opts[:disabled]
   end
end
