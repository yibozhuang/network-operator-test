#!/bin/bash

set -e

CLUSTER_NAME=${1:-netop-test}
CNI_VERSION="v1.3.0"

# Detect architecture
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

CNI_PLUGINS_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz"

echo "Architecture detected: ${ARCH}"
echo "Installing CNI plugins on all nodes"
echo "Using CNI plugins URL: ${CNI_PLUGINS_URL}"

# Get all nodes in the cluster
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

if [ -z "${nodes}" ]; then
    echo "No nodes found in the cluster"
    exit 1
fi

# Install CNI plugins on each node
for node in ${nodes}; do
    echo "=== Installing CNI plugins on node ${node} ==="
    
    echo "Creating CNI directory..."
    docker exec ${node} mkdir -p /opt/cni/bin
    
    echo "Downloading and installing CNI plugins..."
    docker exec ${node} curl -L ${CNI_PLUGINS_URL} | docker exec -i ${node} tar xz -C /opt/cni/bin
    
    echo "Verifying installation..."
    docker exec ${node} ls -l /opt/cni/bin/
    
    # Verify specific plugins we need
    for plugin in macvlan bridge host-local; do
        if docker exec ${node} test -f "/opt/cni/bin/${plugin}"; then
            echo "✅ ${plugin} plugin installed"
        else
            echo "❌ ${plugin} plugin missing"
            exit 1
        fi
    done
done

echo "CNI plugins installation complete!"
echo "Verifying Multus and Whereabouts..."

# Wait for Multus pods
echo "Waiting for Multus pods..."
kubectl wait --for=condition=ready pod -l app=multus -n kube-system --timeout=60s

# Wait for Whereabouts pods
echo "Waiting for Whereabouts pods..."
kubectl wait --for=condition=ready pod -l name=whereabouts -n kube-system --timeout=60s

echo "All CNI components are ready!" 