# Network Operator Test Pods

This directory contains various test pods to validate and understand the network-operator functionality in a kind environment. While these pods can't test actual RDMA/hardware functionality, they help understand the operator's behavior and network configuration capabilities.

## Prerequisites

Before running any test pods, ensure you have the following components installed and configured:

1. **Base Requirements**
   ```bash
   # Create kind cluster with multiple nodes
   kind create cluster --config ../kind-multi-node.yaml

   # Install Network Operator
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update
   
   helm install network-operator nvidia/network-operator \
     -n nvidia-network-operator \
     --create-namespace \
     --version v25.4.0 \
     --wait

   # Verify CRDs are installed
   kubectl get crds | grep mellanox
   
   # Install Whereabouts CNI (required for IP address management)
   helm install whereabouts oci://ghcr.io/k8snetworkplumbingwg/whereabouts-chart
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
   kubectl logs -n nvidia-network-operator -l app=network-operator

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
- Two network definitions (test-network and test-network-2)
- The pod yaml includes the second network definition

```bash
# Verify first network exists
kubectl get network-attachment-definitions

# Apply the test (includes second network definition)
kubectl apply -f 02-multi-network-pod.yaml
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
