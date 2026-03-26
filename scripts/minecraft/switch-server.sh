#!/bin/bash
set -e

#
#/ Usage: switch-server.sh <vanilla|fabric> [-h]
#/ Switch between Vanilla and Fabric servers using the same world
#/
#/ Options:
#/   -h             show this message
#/
#/ Examples:
#/    $ switch-server.sh vanilla
#/    $ switch-server.sh fabric
#

usage() {
    grep '^#/' "${0}" | cut -c 3-
    echo ""
    exit 1
}

if [ $# -eq 0 ] || [ "$1" = "-h" ]; then
    usage
fi

SERVER_TYPE=$1

echo "🔄 Switching to $SERVER_TYPE server..."

case $SERVER_TYPE in
    vanilla)
        echo "⏸️  Stopping Fabric server..."
        sudo k3s kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=0
        
        echo "⏳ Waiting for Fabric server to stop..."
        sudo k3s kubectl wait --for=delete pod -l app=minecraft-fabric -n minecraft-fabric --timeout=60s 2>/dev/null || true
        
        echo "🚀 Starting Vanilla server..."
        sudo k3s kubectl scale deployment minecraft-server -n minecraft --replicas=1
        
        echo "✅ Switched to Vanilla server (port 30565)"
        ;;
        
    fabric)
        echo "⏸️  Stopping Vanilla server..."
        sudo k3s kubectl scale deployment minecraft-server -n minecraft --replicas=0
        
        echo "⏳ Waiting for Vanilla server to stop..."
        sudo k3s kubectl wait --for=delete pod -l app=minecraft -n minecraft --timeout=60s 2>/dev/null || true
        
        echo "🚀 Starting Fabric server..."
        sudo k3s kubectl scale deployment minecraft-fabric-server -n minecraft-fabric --replicas=1
        
        echo "✅ Switched to Fabric server (port 30566)"
        ;;
        
    *)
        echo "❌ Error: Invalid server type. Use 'vanilla' or 'fabric'"
        exit 1
        ;;
esac

echo ""
echo "📝 Server status:"
sudo k3s kubectl get deployments -n minecraft
sudo k3s kubectl get deployments -n minecraft-fabric