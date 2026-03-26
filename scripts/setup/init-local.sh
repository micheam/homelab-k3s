#!/bin/bash
set -e

#
#/ Usage: init_local [-h]
#/ Initialize local configuration files
#/
#/ Prerequisites:
#/   - sops (https://github.com/getsf/sops)
#/   - age key at ~/.config/sops/age/keys.txt
#/
#/ Options:
#/   -h             show this message.
#/
#/ Examples:
#/    $ init_local
#

usage() {
    grep '^#/' "${0}" | cut -c 3-
    echo ""
    exit 1
}

while getopts ":h" opt; do
    case ${opt} in
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
  done

echo "Setting up local configuration files..."

# Check prerequisites
if ! command -v sops &> /dev/null; then
    echo "ERROR: sops is not installed. Install with: brew install sops"
    exit 1
fi

if [ ! -f "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" ]; then
    echo "ERROR: age key not found at ~/.config/sops/age/keys.txt"
    echo "Generate with: age-keygen -o ~/.config/sops/age/keys.txt"
    exit 1
fi

# Decrypt secrets for each app
for app_dir in apps/*/; do
    enc_file="${app_dir}secrets.enc.env"
    dec_file="${app_dir}secrets.env"
    if [ -f "$enc_file" ] && [ ! -f "$dec_file" ]; then
        sops decrypt "$enc_file" > "$dec_file"
        echo "🔓 Decrypted ${dec_file}"
    fi
done

# PV local configuration (node-specific)
if [ ! -f apps/minecraft/pv-local.yaml ]; then
    cp apps/minecraft/pv.yaml.example apps/minecraft/pv-local.yaml
    echo "✏️  Please edit apps/minecraft/pv-local.yaml"
fi

if [ ! -f apps/minecraft-fabric/pv-local.yaml ]; then
    cp apps/minecraft-fabric/pv.yaml.example apps/minecraft-fabric/pv-local.yaml
    echo "✏️  Please edit apps/minecraft-fabric/pv-local.yaml"
fi

if [ ! -f apps/postgres/pv-local.yaml ]; then
    cp apps/postgres/pv.yaml.example apps/postgres/pv-local.yaml
    echo "✏️  Please edit apps/postgres/pv-local.yaml"
fi

echo ""
echo "📝 Next steps:"
echo "1. Edit pv-local.yaml files (update paths and node names)"
echo "2. Deploy: kubectl apply -k apps/<app-name>/"
