#!/usr/bin/env python3

import sys
import time
import signal
from mininet.net import Containernet
from mininet.node import OVSKernelSwitch, RemoteController
from mininet.cli import CLI
from mininet.log import setLogLevel, info
from mininet.link import TCLink


def build_topology():
    net = Containernet(controller=RemoteController, link=TCLink)

    # ------------------------------------------------------------------
    # Controller (Ryu running on localhost:6633)
    # ------------------------------------------------------------------
    info('*** Adding controller\n')
    c0 = net.addController('c0', controller=RemoteController, ip='127.0.0.1', port=6633)

    # ------------------------------------------------------------------
    # Spine Layer (4 switches)
    # ------------------------------------------------------------------
    info('*** Adding spine switches (layer 1): s1-s4\n')
    s1 = net.addSwitch('s1', cls=OVSKernelSwitch, failMode='standalone')
    s2 = net.addSwitch('s2', cls=OVSKernelSwitch, failMode='standalone')
    s3 = net.addSwitch('s3', cls=OVSKernelSwitch, failMode='standalone')
    s4 = net.addSwitch('s4', cls=OVSKernelSwitch, failMode='standalone')

    # ------------------------------------------------------------------
    # Leaf Layer (8 switches) — ASYMMETRIC connections
    # ------------------------------------------------------------------
    info('*** Adding leaf switches (layer 2): s5-s12 (asymmetric)\n')
    s5  = net.addSwitch('s5',  cls=OVSKernelSwitch, failMode='standalone')
    s6  = net.addSwitch('s6',  cls=OVSKernelSwitch, failMode='standalone')
    s7  = net.addSwitch('s7',  cls=OVSKernelSwitch, failMode='standalone')
    s8  = net.addSwitch('s8',  cls=OVSKernelSwitch, failMode='standalone')
    s9  = net.addSwitch('s9',  cls=OVSKernelSwitch, failMode='standalone')
    s10 = net.addSwitch('s10', cls=OVSKernelSwitch, failMode='standalone')
    s11 = net.addSwitch('s11', cls=OVSKernelSwitch, failMode='standalone')
    s12 = net.addSwitch('s12', cls=OVSKernelSwitch, failMode='standalone')

    # ------------------------------------------------------------------
    # Hosts (Docker containers) — varied per leaf
    # ------------------------------------------------------------------
    info('*** Adding hosts (varied distribution)\n')
    hosts_cfg = [
        ('h1',  '10.0.0.1'),  ('h2',  '10.0.0.2'),
        ('h3',  '10.0.0.3'),  ('h4',  '10.0.0.4'),
        ('h5',  '10.0.0.5'),  ('h6',  '10.0.0.6'),
        ('h7',  '10.0.0.7'),  ('h8',  '10.0.0.8'),
        ('h9',  '10.0.0.9'),  ('h10', '10.0.0.10'),
        ('h11', '10.0.0.11'), ('h12', '10.0.0.12'),
        ('h13', '10.0.0.13'), ('h14', '10.0.0.14'),
        ('h15', '10.0.0.15'), ('h16', '10.0.0.16'),
        ('h17', '10.0.0.17'), ('h18', '10.0.0.18'),
        ('h19', '10.0.0.19'), ('h20', '10.0.0.20'),
        ('h21', '10.0.0.21'), ('h22', '10.0.0.22'),
    ]
    hosts = {}
    for name, ip in hosts_cfg:
        hosts[name] = net.addDocker(
            name,
            ip=ip,
            dimage='ubuntu:trusty',
            dcmd='tail -f /dev/null',
        )

    # ------------------------------------------------------------------
    # Links: Spine -> Leaf (ASYMMETRIC: each leaf connects to 2 spines)
    # ------------------------------------------------------------------
    info('*** Adding spine-leaf links (asymmetric)\n')

    # Leaf group 1 (s5-s8) — connect to spines s1-s2
    for leaf in [s5, s6, s7, s8]:
        for spine in [s1, s2]:
            net.addLink(spine, leaf)

    # Leaf group 2 (s9-s12) — connect to spines s3-s4
    for leaf in [s9, s10, s11, s12]:
        for spine in [s3, s4]:
            net.addLink(spine, leaf)

    # ------------------------------------------------------------------
    # Links: Spine-to-Spine (interconnect the two spine groups)
    # ------------------------------------------------------------------
    info('*** Adding spine-spine links (interconnect groups)\n')
    net.addLink(s1, s3)
    net.addLink(s1, s4)
    net.addLink(s2, s3)
    net.addLink(s2, s4)

    # ------------------------------------------------------------------
    # Links: Leaf -> Hosts
    # ------------------------------------------------------------------
    info('*** Adding leaf-host links\n')

    leaf_host_map = {
        s5:  ['h1',  'h2',  'h3',  'h4',  'h5',  'h6'],                    # 6 hosts
        s6:  ['h7',  'h8'],                                                # 2 hosts
        s7:  ['h9',  'h10', 'h11'],                                        # 3 hosts
        s8:  ['h12'],                                                      # 1 host
        s9:  ['h13', 'h14', 'h15', 'h16'],                                 # 4 hosts
        s10: ['h17', 'h18', 'h19'],                                        # 3 hosts
        s11: ['h20'],                                                      # 1 host
        s12: ['h21', 'h22'],                                               # 2 hosts
    }
    for leaf_sw, host_names in leaf_host_map.items():
        for hn in host_names:
            net.addLink(leaf_sw, hosts[hn])

    # ------------------------------------------------------------------
    # Start network
    # ------------------------------------------------------------------
    info('*** Starting network\n')
    net.start()

    # Wait for controller to converge
    info('*** Waiting for Ryu convergence (10s)...\n')
    time.sleep(10)

    info('*** Testing connectivity (pingAll)\n')
    net.pingAll()

    if sys.stdin.isatty():
        info('*** Opening CLI\n')
        CLI(net)
    else:
        info('*** Background mode: network is up. Send SIGTERM to stop.\n')
        def _shutdown(sig, frame):
            net.stop()
            sys.exit(0)
        signal.signal(signal.SIGTERM, _shutdown)
        signal.pause()

    info('*** Stopping network\n')
    net.stop()


if __name__ == '__main__':
    setLogLevel('info')
    build_topology()
