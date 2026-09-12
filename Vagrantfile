# -*- mode: ruby -*-
# vi: set ft=ruby :
# =============================================================================
# Vagrantfile — lab platform for the air-gapped Kubernetes cluster
# =============================================================================
# Purpose:
#   Creates the VMs from ansible/inventory/hosts.yml (topology, ADR-0010)
#   using the box pinned in versions.yaml, and enforces the air gap (ADR-0008):
#
#   1. Networks:    Cluster nodes sit ONLY on the internal "airgap" network.
#                   The bastion (infra) additionally has a host-only network
#                   to the Mac, which is the data diode.
#   2. Cut NAT:     Vagrant needs NIC1 (NAT) for SSH while booting. A trigger
#                   disconnects that link after every "up" and "reload".
#   3. Side channels: Shared folders, clipboard, drag & drop and the Guest
#                   Additions time sync are all disabled.
#   4. No online activity: unattended upgrades are disabled during the first
#                   provisioning run; everything else is installed from the
#                   bundle later on.
#
# Break glass: AIRGAP_SEAL=0 vagrant up  -> NAT stays connected (debug only!)
# =============================================================================

require "yaml"

ROOT      = __dir__
VERSIONS  = YAML.load_file(File.join(ROOT, "versions.yaml"))
INVENTORY = YAML.load_file(File.join(ROOT, "ansible", "inventory", "hosts.yml"))

LAB_VARS   = INVENTORY.dig("all", "vars") || {}
LAB_DOMAIN = LAB_VARS.fetch("lab_domain")
BOX        = VERSIONS.dig("platform", "vagrant_box")

# Order is deliberate: bastion first, then control plane, then workers.
NODE_GROUPS = %w[bastion control_plane workers].freeze

NODES = NODE_GROUPS.flat_map do |group|
  hosts = INVENTORY.dig("all", "children", group, "hosts") || {}
  hosts.map { |name, vars| [name, vars || {}] }
end

abort "No nodes found in inventory (ansible/inventory/hosts.yml)" if NODES.empty?

SEAL_ENABLED = ENV.fetch("AIRGAP_SEAL", "1") != "0"

# /etc/hosts block for all nodes, used until the DNS service on infra is up (M4).
HOSTS_BLOCK = NODES.map do |name, vars|
  "#{vars.fetch('airgap_ip')} #{name}.#{LAB_DOMAIN} #{name}"
end.join("\n")

# Base provisioning: runs only when the VM is created, while NAT is still
# connected. It deliberately downloads nothing.
BASE_SCRIPT = <<~SHELL
  set -euo pipefail

  # 1) No automatic online activity (upgrades, timers, snap refresh)
  systemctl disable --now unattended-upgrades.service 2>/dev/null || true
  systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
  if command -v snap >/dev/null 2>&1; then
    systemctl disable --now snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
  fi

  # 2) Name resolution inside the air gap (idempotent: replaces its own block)
  sed -i '/# airgap-lab BEGIN/,/# airgap-lab END/d' /etc/hosts
  cat >> /etc/hosts <<'EOF'
  # airgap-lab BEGIN
  #{HOSTS_BLOCK}
  # airgap-lab END
  EOF

  echo "Base provisioning complete on $(hostname)"
SHELL

Vagrant.configure("2") do |config|
  config.vm.box              = BOX.fetch("name")
  config.vm.box_version      = BOX.fetch("version")
  config.vm.box_architecture = BOX.fetch("architecture")
  config.vm.box_check_update = false
  config.vm.boot_timeout     = 600

  # Close a side channel: no shared folder between Mac and VMs. Data enters
  # the air gap only through the data diode (scp to infra).
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |name, vars|
    config.vm.define name do |node|
      node.vm.hostname = name

      # NIC2: isolated cluster network (VirtualBox internal network)
      node.vm.network "private_network",
                      ip: vars.fetch("airgap_ip"),
                      virtualbox__intnet: "airgap"

      # NIC3: data diode to the Mac (host-only) — bastion only
      if vars["transfer_ip"]
        node.vm.network "private_network", ip: vars["transfer_ip"]
      end

      node.vm.provider "virtualbox" do |vb|
        vb.name         = "airgap-lab-#{name}"
        vb.cpus         = vars.fetch("vm_cpus", 2)
        vb.memory       = vars.fetch("vm_memory", 4096)
        vb.linked_clone = true

        # Close the time side channel: the VM must NOT take its clock from the
        # Mac. The only time source is chrony on infra (M4).
        vb.customize ["setextradata", :id,
                      "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled", "1"]

        # Close further side channels explicitly (documents the intent)
        vb.customize ["modifyvm", :id,
                      "--clipboard-mode", "disabled",
                      "--drag-and-drop", "disabled"]
      end

      node.vm.provision "base", type: "shell", inline: BASE_SCRIPT

      # Disconnect the NAT link after every boot (ADR-0008)
      if SEAL_ENABLED
        node.trigger.after [:up, :reload] do |t|
          t.info = "Air gap: disconnecting NAT link of #{name}"
          t.run  = { path: File.join(ROOT, "scripts", "airgap.sh"), args: ["seal", name] }
        end
      else
        node.trigger.after [:up, :reload] do |t|
          t.warn = "BREAK GLASS: AIRGAP_SEAL=0 — #{name} stays connected to NAT!"
        end
      end
    end
  end
end
