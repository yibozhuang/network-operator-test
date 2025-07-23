# Network Operator Test Pods

This directory contains various test pods to validate and understand the network-operator functionality in a kind environment. While these pods can't test actual RDMA/hardware functionality, they help understand the operator's behavior and network configuration capabilities.

## Prerequisites

Before running any test pods, ensure you have the following components installed and configured:

1. **Base Requirements**
   ```bash
   # Create kind cluster with multiple nodes
   kind create cluster --config ../kind-multi-node.yaml

   # Install CNI plugins on all nodes
   # Option 1: Using the provided script (recommended)
   ./scripts/install-cni-plugins.sh

   # Option 2: Manual installation
   # Note: This example detects your architecture automatically
   ARCH=$(uname -m)
   case ${ARCH} in
       x86_64)  ARCH="amd64" ;;
       aarch64|arm64) ARCH="arm64" ;;
       *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;;
   esac
   
   for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
     echo "Installing CNI plugins on node ${node}"
     docker exec ${node} mkdir -p /opt/cni/bin
     # Install standard CNI plugins (includes macvlan)
     docker exec ${node} curl -L "https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-${ARCH}-v1.3.0.tgz" | \
       docker exec -i ${node} tar xz -C /opt/cni/bin
   done

   # Install Network Operator
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update
   
   helm install network-operator nvidia/network-operator \
     -n nvidia-network-operator \
     --create-namespace \
     --version v25.4.0 \
     --wait

   # Install Multus CNI
   kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml

   # Install Whereabouts CNI
   helm install whereabouts oci://ghcr.io/k8snetworkplumbingwg/whereabouts-chart

   # Verify CNI installations
   kubectl -n kube-system get pods -l app=multus
   kubectl -n kube-system get pods -l name=whereabouts

   # Verify CNI plugins installation on nodes
   for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
     echo "=== Checking CNI plugins on ${node} ==="
     docker exec ${node} ls -l /opt/cni/bin/
   done
   ```

**Note for Apple Silicon (M1/M2) Users:**
The script and instructions above will automatically detect your ARM64 architecture and download the appropriate CNI plugins. If you're running into any architecture-related issues, verify that:
1. Your kind cluster is running ARM64 nodes (this is automatic on M1/M2 Macs)
2. The downloaded CNI plugins are the ARM64 version
3. All container images support ARM64 architecture

You can verify the architecture of your nodes with:
```bash
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== ${node} architecture ==="
  docker exec ${node} uname -m
done
```

2. **Required Custom Resources**
   ```bash
   # Deploy NicClusterPolicy (required for all network-related tests)
   kubectl apply -f ../example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml

   # Verify NicClusterPolicy status
   kubectl get NicClusterPolicy
   kubectl describe NicClusterPolicy nic-cluster-policy

   # Check if any validation errors occurred
   kubectl get events --field-selector type=Warning

   # If you see validation errors, check the operator logs
   kubectl logs -n nvidia-network-operator -l app.kubernetes.io/name=network-operator

   # Deploy MacvlanNetwork (required for network interface tests)
   kubectl apply -f ../example/crs/mellanox.com_v1alpha1_macvlannetwork_cr.yaml

   # Verify resources are ready
   kubectl get NicClusterPolicy
   kubectl get MacvlanNetwork
   kubectl get network-attachment-definitions -A
   ```

### Troubleshooting CR Installation

If you encounter errors when applying the CRs:

1. **Schema Validation Errors**
   ```bash
   # Check the CRD schema
   kubectl get crd nicclusterpolicies.mellanox.com -o yaml | less

   # Check operator logs for validation details
   kubectl logs -n nvidia-network-operator -l app=network-operator
   ```

2. **Resource Status**
   ```bash
   # Check resource status and events
   kubectl describe NicClusterPolicy nic-cluster-policy
   kubectl get events --field-selector involvedObject.kind=NicClusterPolicy
   ```

3. **Common Issues**
   - Ensure the operator is running before applying CRs
   - Verify CRD versions match your operator version
   - Check that all required fields in CRs are properly formatted
   - Ensure container images and versions are accessible

## Test Pod Dependencies

### 1. Basic Network Test (`01-basic-network-pod.yaml`)
**Required Resources:**
- NicClusterPolicy (status: ready)
- MacvlanNetwork (for the test-network attachment)

```bash
# Verify prerequisites
kubectl get NicClusterPolicy
kubectl get MacvlanNetwork
kubectl get network-attachment-definitions -A

# Apply the test
kubectl apply -f 01-basic-network-pod.yaml
```

### 2. Multi-Network Test (`02-multi-network-pod.yaml`)
**Required Resources:**
- NicClusterPolicy (status: ready)
- Multus CNI installed and running
- Whereabouts CNI installed and running
- The pod yaml includes both network definitions

```bash
# Verify prerequisites
kubectl -n kube-system get pods -l app=multus
kubectl -n kube-system get pods -l name=whereabouts

# Check CNI configuration
for node in $(kubectl get nodes -o name); do
  echo "=== Checking CNI config on ${node} ==="
  kubectl debug ${node#node/} -it --image=busybox -- ls -l /host/etc/cni/net.d/
done

# Apply the test (this will create both network definitions)
kubectl apply -f 02-multi-network-pod.yaml

# Verify network definitions were created
kubectl get network-attachment-definitions
kubectl describe network-attachment-definitions test-network-1
kubectl describe network-attachment-definitions test-network-2

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/multi-network-test --timeout=60s

# Check pod status and networks
kubectl describe pod multi-network-test | grep networks
kubectl logs multi-network-test

# For debugging network issues
kubectl describe pod multi-network-test
kubectl logs -n kube-system -l app=multus
kubectl logs -n kube-system -l name=whereabouts
```

**Expected Output:**
The pod should show three network interfaces:
- eth0: Default Kubernetes network
- net1: From test-network-1 (192.168.1.0/24)
- net2: From test-network-2 (192.168.2.0/24)

**Troubleshooting:**
If networks are not attached:

1. Verify Multus and Whereabouts are running:
   ```bash
   # Check Multus
   kubectl -n kube-system get pods -l app=multus
   kubectl -n kube-system logs -l app=multus
   
   # Check Whereabouts
   kubectl -n kube-system get pods -l name=whereabouts
   kubectl -n kube-system logs -l name=whereabouts
   ```

2. Check network definitions:
   ```bash
   # Get all network definitions
   kubectl get network-attachment-definitions -o yaml
   
   # Check events
   kubectl get events --field-selector involvedObject.kind=NetworkAttachmentDefinition
   ```

3. Check CNI configuration on nodes:
   ```bash
   # Debug on a specific node
   NODE_NAME=$(kubectl get pod multi-network-test -o jsonpath='{.spec.nodeName}')
   kubectl debug node/$NODE_NAME -it --image=busybox -- chroot /host sh -c \
     "ls -l /etc/cni/net.d/ && cat /etc/cni/net.d/*.conf*"
   ```

4. Check pod annotations and events:
   ```bash
   # Check pod annotations
   kubectl get pod multi-network-test -o jsonpath='{.metadata.annotations}' | jq
   
   # Check pod events
   kubectl get events --field-selector involvedObject.name=multi-network-test
   ```

### 3. Resource Test (`03-resource-test-pod.yaml`)
**Required Resources:**
- NicClusterPolicy (status: ready)
- RDMA Device Plugin enabled in NicClusterPolicy

```bash
# Verify RDMA resources are available
kubectl get NicClusterPolicy
kubectl describe node | grep nvidia.com/rdma

# Apply the test
kubectl apply -f 03-resource-test-pod.yaml
```

### 4. Operator Validation (`04-operator-validation-pod.yaml`)
**Required Resources:**
- Only requires the operator to be running
- No additional CRs needed

```bash
# Verify operator is running
kubectl get pods -n nvidia-network-operator

# Apply the test
kubectl apply -f 04-operator-validation-pod.yaml
```

## Running All Tests in Sequence

Here's the complete sequence to set up and run all tests:

```bash
# 1. Create cluster and install operator
kind create cluster --config ../kind-multi-node.yaml

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install network-operator nvidia/network-operator \
  -n nvidia-network-operator \
  --create-namespace \
  --version v25.4.0 \
  --wait

# 2. Deploy required CRs
kubectl apply -f ../example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml
kubectl apply -f ../example/crs/mellanox.com_v1alpha1_macvlannetwork_cr.yaml

# 3. Wait for resources to be ready
echo "Waiting for NicClusterPolicy to be ready..."
kubectl wait --for=condition=ready NicClusterPolicy --all --timeout=300s

echo "Waiting for network attachments to be available..."
kubectl wait --for=condition=established crd/network-attachment-definitions.k8s.cni.cncf.io --timeout=60s

# 4. Apply test pods in sequence
kubectl apply -f 01-basic-network-pod.yaml
kubectl wait --for=condition=ready pod/basic-network-test --timeout=60s

kubectl apply -f 02-multi-network-pod.yaml
kubectl wait --for=condition=ready pod/multi-network-test --timeout=60s

kubectl apply -f 03-resource-test-pod.yaml
kubectl wait --for=condition=ready pod/resource-test --timeout=60s

kubectl apply -f 04-operator-validation-pod.yaml
kubectl wait --for=condition=ready pod/operator-validation --timeout=60s

# 5. Monitor results
kubectl get pods -w
```

## Verifying Test Results

For each test pod, you can verify the results:

```bash
# Basic Network Test
kubectl logs basic-network-test

# Multi-Network Test
kubectl logs multi-network-test
kubectl exec -it multi-network-test -- ip addr show

# Resource Test
kubectl logs resource-test
kubectl describe pod resource-test

# Operator Validation
kubectl logs -f operator-validation
```

## Troubleshooting

### Common Issues

1. **Pods Stuck in Pending State**
   ```bash
   # Check node resources
   kubectl describe node
   # Check for network attachment issues
   kubectl describe pod <pod-name>
   ```

2. **Network Attachment Issues**
   ```bash
   # Verify network definitions
   kubectl get network-attachment-definitions -A
   # Check CNI configuration
   kubectl get NicClusterPolicy
   ```

3. **Resource Allocation Issues**
   ```bash
   # Check available resources
   kubectl describe node | grep nvidia.com
   # Verify device plugin status
   kubectl get pods -n nvidia-network-operator
   ```

## Cleanup

```bash
# Delete test pods
kubectl delete -f ./

# Remove CRs
kubectl delete -f ../example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml
kubectl delete -f ../example/crs/mellanox.com_v1alpha1_macvlannetwork_cr.yaml

# Uninstall operator
helm uninstall -n nvidia-network-operator network-operator

# Delete cluster
kind delete cluster --name netop-test-multi
```

## Test Pod Features

1. **Network Troubleshooting Tools**
   - All pods use `nicolaka/netshoot` image
   - Contains common networking tools
   - Includes debugging utilities

2. **Monitoring Capabilities**
   - Real-time network interface monitoring
   - Resource usage tracking
   - Operator status checking

3. **Resource Management**
   - Tests various resource requests
   - Validates resource limits
   - Checks device plugin functionality

4. **Network Configuration**
   - Tests multiple network attachments
   - Validates routing configurations
   - Checks CNI plugin functionality

## Expected Results

1. **Basic Network Test**
   - Should show additional network interface
   - Should have correct IP address
   - Should have proper routing table

2. **Multi-Network Test**
   - Should show multiple interfaces
   - Should have separate IP addresses
   - Should have correct routing rules

3. **Resource Test**
   - Should show resource requests
   - May show "device not found" (expected in kind)
   - Should respect CPU/memory limits

4. **Operator Validation**
   - Should show operator running
   - Should list expected CRDs
   - Should show network configurations

## Troubleshooting

1. **Pod Pending State**
   - Check node resources
   - Verify operator status
   - Check for network plugin errors

2. **Network Issues**
   - Verify NetworkAttachmentDefinition
   - Check CNI configuration
   - Validate network plugin logs

3. **Resource Problems**
   - Verify NicClusterPolicy
   - Check device plugin status
   - Validate resource availability
