# Class: sdn_topology
# Installs Docker and deploys the SDN topology via docker compose.
class sdn_topology (
  String $topology_dir = '/home/ubuntu/sdn-topology',
  String $docker_user  = 'ubuntu',
) {

  # Path to ONOS files inside sdn-topology/ (3 levels up from this module)
  $onos_src = "${module_directory('sdn_topology')}/../../../sdn-topology/fat-tree/onos"

  # ------------------------------------------------------------------
  # Install OVS kernel module
  # ------------------------------------------------------------------
  exec { 'apt_update':
    command => '/usr/bin/apt-get update',
  }

  package { ['linux-modules-extra-aws', 'openvswitch-switch']:
    ensure  => present,
    require => Exec['apt_update'],
  }

  exec { 'load_ovs':
    command => '/sbin/modprobe openvswitch',
    unless  => '/bin/bash -c "lsmod | grep -q ^openvswitch"',
    require => Package['openvswitch-switch'],
  }

  # ------------------------------------------------------------------
  # Install Docker
  # ------------------------------------------------------------------
  package { ['ca-certificates', 'curl', 'gnupg']:
    ensure  => present,
    require => Exec['apt_update'],
  }

  exec { 'add_docker_gpg':
    command => '/bin/bash -c "install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && chmod a+r /etc/apt/keyrings/docker.gpg"',
    creates => '/etc/apt/keyrings/docker.gpg',
    require => Package['curl'],
  }

  exec { 'add_docker_repo':
    command => '/bin/bash -c "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" | tee /etc/apt/sources.list.d/docker.list && apt-get update"',
    creates => '/etc/apt/sources.list.d/docker.list',
    require => Exec['add_docker_gpg'],
  }

  package { ['docker-ce', 'docker-ce-cli', 'containerd.io', 'docker-compose-plugin']:
    ensure  => present,
    require => Exec['add_docker_repo'],
  }

  service { 'docker':
    ensure  => running,
    enable  => true,
    require => Package['docker-ce'],
  }

  user { $docker_user:
    ensure  => present,
    groups  => ['docker'],
    require => Service['docker'],
  }

  # ------------------------------------------------------------------
  # Deploy topology files directly from sdn-topology/
  # ------------------------------------------------------------------
  file { "${topology_dir}/onos":
    ensure  => directory,
    owner   => $docker_user,
    group   => $docker_user,
    mode    => '0755',
    require => Service['docker'],
  }

  file { "${topology_dir}/onos/docker-compose.yml":
    content => file("${onos_src}/docker-compose.yml"),
    owner   => $docker_user,
    group   => $docker_user,
    mode    => '0644',
    require => File["${topology_dir}/onos"],
  }

  file { "${topology_dir}/onos/topology.py":
    content => file("${onos_src}/topology.py"),
    owner   => $docker_user,
    group   => $docker_user,
    mode    => '0644',
    require => File["${topology_dir}/onos"],
  }

  file { "${topology_dir}/onos/start.sh":
    content => file("${onos_src}/start.sh"),
    owner   => $docker_user,
    group   => $docker_user,
    mode    => '0755',
    require => File["${topology_dir}/onos"],
  }

  # ------------------------------------------------------------------
  # Run docker compose
  # ------------------------------------------------------------------
  exec { 'docker_compose_up':
    command     => 'docker compose up -d',
    cwd         => "${topology_dir}/onos",
    path        => ['/usr/bin', '/usr/local/bin'],
    user        => $docker_user,
    environment => ["HOME=/home/${docker_user}"],
    require     => [
      File["${topology_dir}/onos/docker-compose.yml"],
      File["${topology_dir}/onos/start.sh"],
      File["${topology_dir}/onos/topology.py"],
    ],
  }
}
