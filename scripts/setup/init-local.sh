#!/bin/bash
set -e

#
#/ Usage: init_local [-h]
#/ Initialize local configuration files
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

# Minecraft config
if [ ! -f apps/minecraft/config.env ]; then
    cp apps/minecraft/config.env.example apps/minecraft/config.env
    echo "✏️  Please edit apps/minecraft/config.env"
fi

if [ ! -f apps/minecraft/pv-local.yaml ]; then
    cp apps/minecraft/pv.yaml.example apps/minecraft/pv-local.yaml
    echo "✏️  Please edit apps/minecraft/pv-local.yaml"
fi

# Minecraft Fabric config
if [ ! -f apps/minecraft-fabric/config.env ]; then
    cp apps/minecraft-fabric/config.env.example apps/minecraft-fabric/config.env
    echo "✏️  Please edit apps/minecraft-fabric/config.env"
fi

if [ ! -f apps/minecraft-fabric/pv-local.yaml ]; then
    cp apps/minecraft-fabric/pv.yaml.example apps/minecraft-fabric/pv-local.yaml
    echo "✏️  Please edit apps/minecraft-fabric/pv-local.yaml"
fi

echo ""
echo "📝 Next steps:"
echo "1. Edit the local configuration files"
echo "2. Update paths and node names"
echo "3. Set secure passwords"
echo "4. Run: kubectl apply -k apps/minecraft/"
