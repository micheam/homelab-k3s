# Home Lab K3s GitOps

A GitOps repository for managing home lab applications on K3s.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/micheam/homelab-k3s.git
cd homelab-k3s

# Initialize local files (decrypt secrets, create pv-local.yaml)
# Requires: sops, age key at ~/.config/sops/age/keys.txt
./scripts/setup/init-local.sh

# Deploy an application (local kubeconfig is read-only; apply on the k3s node)
kubectl kustomize apps/postgres/ | ssh <k3s-node> 'KUBECONFIG=$HOME/.kube/config kubectl apply -f -'
```
