# ansible_kube

Builds a small Kubernetes test cluster on local KVM/libvirt virtual machines.
A shell script clones the VMs, then Ansible playbooks install Kubernetes on
them with `kubeadm` and set up the Flannel pod network.

The versions used (Kubernetes 1.7.5, CentOS/RHEL 7 yum repos) date from
around 2017. See [Known issues](#known-issues) before running it today.

## Requirements

- A libvirt host with `virt-clone` and `virsh`.
- A CentOS/RHEL 7 template VM with root SSH login enabled.
- Ansible on the control machine.
- An SSH key pair named `ans_ssh` / `ans_ssh.pub` in the repo root
  (gitignored), for example:

  ```
  ssh-keygen -f ans_ssh -N ''
  ```

## Repository layout

| File | Purpose |
|------|---------|
| `createnodes.sh` | Clones and starts the VMs, then writes `./inventory` |
| `key_install.yaml` | Installs `ans_ssh.pub` for root on every host |
| `upkub.yml` | Prepares all hosts, initializes the master, installs Flannel |
| `join_nodes.yml` | Joins the worker nodes to the master |
| `group_vars/all` | Holds `join_token`, used by `join_nodes.yml` |
| `templates/*.repo` | Yum repo definitions copied to the hosts |
| `ansible.cfg` | Turns off SSH host key checking |

## Usage

### 1. Create the VMs

```
./createnodes.sh -n <workers 1-5> -p <name prefix> -t <template VM>
```

- Clones the template into `<PREFIX>master` and `<PREFIX>node1..N` with
  `virt-clone` and starts each VM with `virsh start`.
- Checks `virsh domifaddr` every 5 seconds until each VM has an IP address
  (it uses the first interface only).
- Appends three groups to `./inventory`: `[cluster]` (all VMs), `[master]`
  and `[nodes]`. Each host gets a `hostname=` variable.

### 2. Install the SSH key

```
ansible-playbook -i inventory key_install.yaml -k
```

Adds `ans_ssh.pub` to root's `authorized_keys` on every host. `-k` asks for
the root password, since key login isn't set up yet.

### 3. Install Kubernetes

```
ansible-playbook -i inventory --private-key ans_ssh upkub.yml
```

This runs three plays:

1. **All cluster hosts:** stops and disables firewalld, sets SELinux to
   permissive, sets the hostname from the inventory, installs and starts
   Docker, adds the Kubernetes yum repos, installs `kubectl`, `kubelet` and
   `kubeadm` at version 1.7.5, and starts kubelet.
2. **Master:** runs `kubeadm init --pod-network-cidr=10.244.0.0/16` unless
   `/etc/kubernetes/admin.conf` or `/var/lib/kubelet` already exists. It then
   creates a `kubeta` user, installs the SSH key for that user, and copies
   `admin.conf` to `~kubeta/.kube/config`.
3. **Master, as `kubeta`:** installs Flannel with `kubectl apply`. The
   10.244.0.0/16 CIDR is Flannel's default.

### 4. Join the workers

```
ansible-playbook -i inventory --private-key ans_ssh join_nodes.yml
```

Runs `kubeadm join --token {{ join_token }} <master-ip>:6443` on each
worker. Note the token problem described below.

## Known issues

### Bugs

- **The join token never matches.** `join_nodes.yml` uses the fixed token in
  `group_vars/all`, but `kubeadm init` is never passed `--token {{ join_token }}`,
  so it generates a random one. Joining fails unless the token is edited by hand.
- **The `creates:` guards don't work.** Nothing creates
  `/tmp/joined_kubernetes` or `/tmp/flannel.installed`, so both tasks run on
  every run. Running `join_nodes.yml` again on a node that has already joined
  errors out.
- **`createnodes.sh` checks `-t` wrongly.** The `-t` case validates `$PREFIX`
  instead of `$VMTEMPLATE` (a copy-paste mistake).
- **`createnodes.sh` ignores bad options.** Invalid options (`\?`) and
  missing arguments (`:`) print an error but don't exit.
- **The inventory grows on every run.** The script appends with
  `>> ./inventory`, so each run adds duplicate host entries.
- **A required kernel setting is missing.** `br_netfilter` isn't loaded and
  `net.bridge.bridge-nf-call-iptables=1` isn't set. Flannel and kubeadm
  normally need both.

### Out of date or insecure

- **The package repos are gone.** The `packages.cloud.google.com` yum repos
  have been shut down; the replacement is `pkgs.k8s.io`. Kubernetes 1.7.5 and
  the distro `docker` package are long past end of life.
- **No package signature checks.** Both repo files set `gpgcheck=0` and
  `repo_gpgcheck=0`.
- **An unneeded repo.** The Google Cloud SDK repo isn't used by anything here.
- **Newer Kubernetes needs more steps.** Versions after 1.8 require swap to be
  turned off, and `kubeadm join` there needs `--discovery-token-ca-cert-hash`.
  Neither is handled.
