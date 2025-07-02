# Home Lab K3s GitOps

A GitOps repository for managing home lab applications on K3s (Fedora Asahi Linux on Apple M1 Mac mini).

## Quick Start

1. Fork and clone this repository
2. Initialize local configurations:
   ```bash
   ./scripts/setup/init-local.sh
   ```
4. Edit the generated local files
  * `apps/minecraft/config.env`
  * `apps/minecraft/pv-local.yaml`
5. Deploy applications
  ```bash
  # Manually apply the local files
  kubectl apply -f apps/minecraft/

  # Or with ArgoCD (NOT WORKING YET)
  kubectl apply -f apps/argocd/applications/minecraft.yaml
  ```

## Security Notes

This repository is designed to be public. All sensitive information should be stored in local files that are excluded by `.gitignore`.

Never commit:
- Passwords or secrets
- Internal IP addresses
- Personal usernames
- Local file paths

## Roadmap 

- [ ] use Sealed Secrets for secrets management
