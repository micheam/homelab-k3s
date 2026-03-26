#!/bin/bash
set -e

#
#/ Usage: migrate-to-fabric.sh [-h] [-b]
#/ Migrate vanilla Minecraft world to Fabric server
#/
#/ Options:
#/   -h             show this message
#/   -b             backup only (don't stop vanilla server)
#/
#/ Examples:
#/    $ migrate-to-fabric.sh
#/    $ migrate-to-fabric.sh -b
#

usage() {
    grep '^#/' "${0}" | cut -c 3-
    echo ""
    exit 1
}

BACKUP_ONLY=false

while getopts ":hb" opt; do
    case ${opt} in
        h)
            usage
            ;;
        b)
            BACKUP_ONLY=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Configuration
VANILLA_DATA_PATH="/home/micheam/minecraft-data"
FABRIC_DATA_PATH="/home/micheam/minecraft-fabric"
BACKUP_PATH="${HOME}/minecraft-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🔄 Starting Minecraft world migration to Fabric server..."

# Create backup directory
mkdir -p "$BACKUP_PATH"

# Check if vanilla server is running
VANILLA_POD=$(sudo k3s kubectl get pods -n minecraft -l app=minecraft -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$VANILLA_POD" ]; then
    echo "⚠️  Warning: Vanilla Minecraft server pod not found"
else
    echo "✅ Found vanilla server pod: $VANILLA_POD"
fi

# Stop vanilla server if not backup-only mode
if [ "$BACKUP_ONLY" = false ] && [ -n "$VANILLA_POD" ]; then
    echo "⏸️  Scaling down vanilla Minecraft server..."
    sudo k3s kubectl scale deployment minecraft-server -n minecraft --replicas=0
    
    # Wait for pod to terminate
    echo "⏳ Waiting for vanilla server to stop..."
    sudo k3s kubectl wait --for=delete pod -l app=minecraft -n minecraft --timeout=60s 2>/dev/null || true
fi

# Create backup of vanilla world
echo "💾 Creating backup of vanilla world..."
if [ -d "$VANILLA_DATA_PATH" ]; then
    sudo tar -czf "$BACKUP_PATH/vanilla-world-${TIMESTAMP}.tar.gz" -C "$VANILLA_DATA_PATH" .
    echo "✅ Backup created: $BACKUP_PATH/vanilla-world-${TIMESTAMP}.tar.gz"
else
    echo "❌ Error: Vanilla data path not found: $VANILLA_DATA_PATH"
    exit 1
fi

# Create Fabric data directory if it doesn't exist
echo "📁 Preparing Fabric data directory..."
sudo mkdir -p "$FABRIC_DATA_PATH"
sudo chown -R $(id -u):$(id -g) "$FABRIC_DATA_PATH"

# Check if Fabric server is running and stop it
FABRIC_POD=$(sudo k3s kubectl get pods -n minecraft-fabric -l app=minecraft-fabric -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$FABRIC_POD" ]; then
    echo "⏸️  Scaling down Fabric server..."
    sudo k3s kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=0
    
    # Wait for pod to terminate
    echo "⏳ Waiting for Fabric server to stop..."
    sudo k3s kubectl wait --for=delete pod -l app=minecraft-fabric -n minecraft-fabric --timeout=60s 2>/dev/null || true
fi

# Copy world data to Fabric directory
if [ "$BACKUP_ONLY" = false ]; then
    echo "📋 Copying world data to Fabric server..."
    
    # Backup existing Fabric data if it exists
    if [ -d "$FABRIC_DATA_PATH/world" ]; then
        echo "💾 Backing up existing Fabric world..."
        sudo tar -czf "$BACKUP_PATH/fabric-world-${TIMESTAMP}.tar.gz" -C "$FABRIC_DATA_PATH" .
    fi
    
    # Copy vanilla world to Fabric
    sudo cp -r "$VANILLA_DATA_PATH"/* "$FABRIC_DATA_PATH/" 2>/dev/null || true
    
    # Ensure proper permissions
    sudo chown -R 1000:1000 "$FABRIC_DATA_PATH"
    
    echo "✅ World data copied to Fabric server"
    
    # Scale up Fabric server
    echo "🚀 Starting Fabric server with migrated world..."
    sudo k3s kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=1
    
    echo ""
    echo "✨ Migration complete!"
    echo ""
    echo "📝 Next steps:"
    echo "1. Wait for Fabric server to start: sudo k3s kubectl logs -n minecraft-fabric -l app=minecraft-fabric -f"
    echo "2. Test connection to Fabric server on port 30566"
    echo "3. Verify world data is intact"
    echo ""
    echo "🔄 To restore vanilla server: sudo k3s kubectl scale deployment minecraft-server -n minecraft --replicas=1"
else
    echo ""
    echo "✅ Backup complete!"
    echo "📁 Backup location: $BACKUP_PATH/vanilla-world-${TIMESTAMP}.tar.gz"
    echo ""
    echo "To complete migration, run: $0"
fi