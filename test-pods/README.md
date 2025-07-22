# Network Operator Test Pods

This directory contains various test pods to validate and understand the network-operator functionality in a kind environment. While these pods can't test actual RDMA/hardware functionality, they help understand the operator's behavior and network configuration capabilities.

## Test Scenarios

### 1. Basic Network Test (`01-basic-network-pod.yaml`)
Tests basic network attachment and configuration:
- Network interface creation
- IP address assignment
- Routing table configuration

```bash
# Apply the test
kubectl apply -f 01-basic-network-pod.yaml

# Check pod status
kubectl get pod basic-network-test

# View network configuration
kubectl logs basic-network-test
```

### 2. Multi-Network Test (`02-multi-network-pod.yaml`)
Tests multiple network attachment capabilities:
- Multiple interface creation
- Multiple IP assignments
- Routing between networks

```bash
# Apply the test
kubectl apply -f 02-multi-network-pod.yaml

# Check pod status
kubectl get pod multi-network-test

# View network configurations
kubectl logs multi-network-test

# Test specific interface
kubectl exec -it multi-network-test -- ip addr show net1
kubectl exec -it multi-network-test -- ip addr show net2
```

### 3. Resource Test (`03-resource-test-pod.yaml`)
Tests resource allocation and limits:
- RDMA resource requests
- GPU resource requests
- CPU/Memory limits
- Device discovery

```bash
# Apply the test
kubectl apply -f 03-resource-test-pod.yaml

# Check pod status and resource allocation
kubectl get pod resource-test
kubectl describe pod resource-test

# View resource information
kubectl logs resource-test
```

### 4. Operator Validation (`04-operator-validation-pod.yaml`)
Continuously monitors operator status and configuration:
- Operator pod status
- CRD availability
- Network plugin configuration
- Configuration changes

```bash
# Apply the test
kubectl apply -f 04-operator-validation-pod.yaml

# View ongoing validation results
kubectl logs -f operator-validation

# Check specific components
kubectl exec -it operator-validation -- ls -l /etc/cni/net.d/
```

## Running All Tests

To run all tests in sequence:

```bash
# Create kind cluster with multiple nodes
kind create cluster --config ../kind-multi-node.yaml

# Deploy network operator
kubectl apply -k ../deployments/kustomization/base

# Apply all test pods
kubectl apply -f ./

# Monitor results
kubectl get pods -w
```

## Cleanup

To clean up all test resources:

```bash
# Delete all test pods
kubectl delete -f ./

# Delete kind cluster
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