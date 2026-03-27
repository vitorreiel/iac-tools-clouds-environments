topology_dir = node['sdn_topology']['topology_dir']
docker_user  = node['sdn_topology']['docker_user']
topology_type = node['sdn_topology']['topology_type'] || 'fat-tree'

onos_src = "/tmp/sdn-topology/#{topology_type}/onos"

# ------------------------------------------------------------------
# Install OVS kernel module
# ------------------------------------------------------------------
apt_update 'update'

%w[linux-modules-extra-aws openvswitch-switch].each do |pkg|
  package pkg
end

execute 'load_ovs' do
  command 'modprobe openvswitch'
  not_if  'lsmod | grep -q "^openvswitch"'
end

# ------------------------------------------------------------------
# Install Docker
# ------------------------------------------------------------------
%w[ca-certificates curl gnupg].each do |pkg|
  package pkg
end

execute 'add_docker_gpg' do
  command <<~CMD
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  CMD
  not_if { ::File.exist?('/etc/apt/keyrings/docker.gpg') }
end

execute 'add_docker_repo' do
  command <<~CMD
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
    tee /etc/apt/sources.list.d/docker.list
  CMD
  not_if { ::File.exist?('/etc/apt/sources.list.d/docker.list') }
end

apt_update 'update_after_docker_repo' do
  action :update
end

%w[docker-ce docker-ce-cli containerd.io docker-compose-plugin].each do |pkg|
  package pkg
end

service 'docker' do
  action [:enable, :start]
end

execute 'record_install_done' do
  command 'date +%s%N > /tmp/t_install_done'
end

group 'docker' do
  members [docker_user]
  append  true
end

# ------------------------------------------------------------------
# Deploy topology files directly from sdn-topology/
# ------------------------------------------------------------------
directory "#{topology_dir}/onos" do
  owner     docker_user
  group     docker_user
  mode      '0755'
  recursive true
end

{ 'docker-compose.yml' => '0644', 'topology.py' => '0644', 'start.sh' => '0755' }.each do |f, mode|
  file "#{topology_dir}/onos/#{f}" do
    content ::File.read("#{onos_src}/#{f}")
    owner   docker_user
    group   docker_user
    mode    mode
  end
end

# ------------------------------------------------------------------
# Run docker compose
# ------------------------------------------------------------------
execute 'docker_compose_up' do
  command     "sudo -u #{docker_user} sg docker -c 'docker compose up -d'"
  cwd         "#{topology_dir}/onos"
  environment({ 'HOME' => "/home/#{docker_user}" })
end
