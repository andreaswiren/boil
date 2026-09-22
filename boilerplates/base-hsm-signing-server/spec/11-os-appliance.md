# OS Appliance Management

`signzone-osd` runs as root but implements typed operations only. Network/firewall changes use candidate configuration + rollback timer + confirmation. SSH is disabled by default. Admin UI supports hostname, DNS, NTP, interfaces, routes, VLANs, nftables, updates, service status/restart allowlist, storage, journal views and support bundles. No browser shell.
