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
    # Controller (ONOS running on localhost:6653)
    # ------------------------------------------------------------------
    info('*** Adding controller\n')
    c0 = net.addController('c0', controller=RemoteController, ip='127.0.0.1', port=6653)

    # ------------------------------------------------------------------
    # Layer 1 - core switches
    # ------------------------------------------------------------------
    info('*** Adding core switches (layer 1): s1-s4\n')
    s1 = net.addSwitch('s1', cls=OVSKernelSwitch, failMode='secure')
    s2 = net.addSwitch('s2', cls=OVSKernelSwitch, failMode='secure')
    s3 = net.addSwitch('s3', cls=OVSKernelSwitch, failMode='secure')
    s4 = net.addSwitch('s4', cls=OVSKernelSwitch, failMode='secure')

    # ------------------------------------------------------------------
    # Layer 2 - aggregation switches
    # ------------------------------------------------------------------
    info('*** Adding aggregation switches (layer 2): s5-s12\n')
    s5  = net.addSwitch('s5',  cls=OVSKernelSwitch, failMode='secure')
    s6  = net.addSwitch('s6',  cls=OVSKernelSwitch, failMode='secure')
    s7  = net.addSwitch('s7',  cls=OVSKernelSwitch, failMode='secure')
    s8  = net.addSwitch('s8',  cls=OVSKernelSwitch, failMode='secure')
    s9  = net.addSwitch('s9',  cls=OVSKernelSwitch, failMode='secure')
    s10 = net.addSwitch('s10', cls=OVSKernelSwitch, failMode='secure')
    s11 = net.addSwitch('s11', cls=OVSKernelSwitch, failMode='secure')
    s12 = net.addSwitch('s12', cls=OVSKernelSwitch, failMode='secure')

    # ------------------------------------------------------------------
    # Layer 3 - edge switches
    # ------------------------------------------------------------------
    info('*** Adding edge switches (layer 3): s13-s20\n')
    s13 = net.addSwitch('s13', cls=OVSKernelSwitch, failMode='secure')
    s14 = net.addSwitch('s14', cls=OVSKernelSwitch, failMode='secure')
    s15 = net.addSwitch('s15', cls=OVSKernelSwitch, failMode='secure')
    s16 = net.addSwitch('s16', cls=OVSKernelSwitch, failMode='secure')
    s17 = net.addSwitch('s17', cls=OVSKernelSwitch, failMode='secure')
    s18 = net.addSwitch('s18', cls=OVSKernelSwitch, failMode='secure')
    s19 = net.addSwitch('s19', cls=OVSKernelSwitch, failMode='secure')
    s20 = net.addSwitch('s20', cls=OVSKernelSwitch, failMode='secure')

    # ------------------------------------------------------------------
    # Hosts (Docker containers)
    # ------------------------------------------------------------------
    info('*** Adding hosts (h1-h16)\n')
    hosts_cfg = [
        ('h1',  '10.0.0.1'),  ('h2',  '10.0.0.2'),
        ('h3',  '10.0.0.3'),  ('h4',  '10.0.0.4'),
        ('h5',  '10.0.0.5'),  ('h6',  '10.0.0.6'),
        ('h7',  '10.0.0.7'),  ('h8',  '10.0.0.8'),
        ('h9',  '10.0.0.9'),  ('h10', '10.0.0.10'),
        ('h11', '10.0.0.11'), ('h12', '10.0.0.12'),
        ('h13', '10.0.0.13'), ('h14', '10.0.0.14'),
        ('h15', '10.0.0.15'), ('h16', '10.0.0.16'),
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
    # Links: Layer 1 -> Layer 2  (full mesh - each core to all agg)
    # ------------------------------------------------------------------
    info('*** Adding links: core -> aggregation\n')

    for core in [s1, s2, s3, s4]:
        for agg in [s5, s6, s7, s8, s9, s10, s11, s12]:
            net.addLink(core, agg)

    # ------------------------------------------------------------------
    # Links: Layer 2 -> Layer 3  (cross-links)
    # ------------------------------------------------------------------
    info('*** Adding links: aggregation -> edge\n')

    # Left group
    for agg in [s5, s6]:
        for edge in [s13, s14]:
            net.addLink(agg, edge)

    for agg in [s7, s8]:
        for edge in [s15, s16]:
            net.addLink(agg, edge)

    # Right group
    for agg in [s9, s10]:
        for edge in [s17, s18]:
            net.addLink(agg, edge)

    for agg in [s11, s12]:
        for edge in [s19, s20]:
            net.addLink(agg, edge)

    # ------------------------------------------------------------------
    # Links: Layer 3 -> Hosts
    # ------------------------------------------------------------------
    info('*** Adding links: edge -> hosts\n')

    edge_host_map = {
        s13: ['h1',  'h2'],
        s14: ['h3',  'h4'],
        s15: ['h5',  'h6'],
        s16: ['h7',  'h8'],
        s17: ['h9',  'h10'],
        s18: ['h11', 'h12'],
        s19: ['h13', 'h14'],
        s20: ['h15', 'h16'],
    }
    for edge_sw, host_names in edge_host_map.items():
        for hn in host_names:
            net.addLink(edge_sw, hosts[hn])

    # ------------------------------------------------------------------
    # Start network
    # ------------------------------------------------------------------
    info('*** Starting network\n')
    net.start()

    # ONOS spanning-tree app handles loop prevention - wait for it to converge
    info('*** Waiting for ONOS spanning-tree convergence (20s)...\n')
    time.sleep(20)

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
