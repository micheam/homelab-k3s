# Home Lab K3s GitOps

A GitOps repository for managing home lab applications on K3s.

## 📚 Documentation

All documentation is available in the **[Wiki](https://github.com/micheam/homelab-k3s/wiki)**.

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/micheam/homelab-k3s.git
cd homelab-k3s

# Initialize local configurations
./scripts/setup/init-local.sh

# Deploy an application
kubectl apply -k apps/minecraft/
