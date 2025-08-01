# Network Operator Testing Guide

This repository contains testing instructions and examples for the [Mellanox Network Operator](https://github.com/Mellanox/network-operator). The guide covers both local testing using kind (Kubernetes in Docker) and cloud-based testing with real hardware.

## Table of Contents
- [Local Testing with kind](#local-testing-with-kind)
  - [Prerequisites](#prerequisites)
  - [Step-by-Step Local Testing](#step-by-step-local-testing)
- [Cloud Testing Options](#cloud-testing-options)
  - [Option 1: Azure (Most Common)](#option-1-azure)
    - [Prerequisites for Azure](#prerequisites-for-azure)
    - [Step-by-Step Azure Testing](#step-by-step-azure-testing)
  - [Option 2: Oracle Cloud Infrastructure (OCI) - Simpler Alternative](#option-2-oracle-cloud-infrastructure)
    - [Prerequisites for OCI](#prerequisites-for-oci)
    - [Step-by-Step OCI Testing](#step-by-step-oci-testing)
  - [Option 3: Google Cloud Platform (GCP)](#option-3-google-cloud-platform)
- [Cloud Provider Comparison](#cloud-provider-comparison)
- [Recommendations](#recommendations)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Local Testing with kind

### Prerequisites

Before starting, ensure you have the following tools installed:

```bash
# For macOS users
brew install kind
brew install kubectl
brew install helm  # Added Helm requirement
brew install docker  # Or Docker Desktop

# Verify installations
kind --version
kubectl version
helm version
docker --version
```

Additional requirements:
- Git
- Go (optional, for building from source)
- Access to pull container images

### Step-by-Step Local Testing

1. **Clone the Network Operator Repository**
   ```bash
   git clone https://github.com/Mellanox/network-operator.git
   cd network-operator
   ```

2. **Create a kind Cluster**
   ```bash
   # Create a new cluster
   kind create cluster --name netop-test
   
   # Verify cluster is running
   kubectl cluster-info --context kind-netop-test
   ```

3. **Deploy the Network Operator using Helm**
   ```bash
   # Add the NVIDIA Networking Helm repository
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update

   # Get the latest version available
   helm search repo nvidia/network-operator -l | head -n 5

   # Install the network operator (includes CRDs)
   helm install network-operator nvidia/network-operator \
      -n nvidia-network-operator \
      --create-namespace \
      --version v25.4.0 \
      --wait
   
   # Verify operator deployment and CRDs
   kubectl get pods -n nvidia-network-operator
   kubectl get crds | grep mellanox

   # Check operator logs if there are issues
   kubectl logs -n nvidia-network-operator -l name=network-operator
   ```

4. **Deploy NicClusterPolicy**
   ```bash
   # Apply example NicClusterPolicy
   kubectl apply -f example/crs/mellanox.com_v1alpha1_nicclusterpolicy_cr.yaml
   
   # Verify policy status
   kubectl get NicClusterPolicy
   kubectl describe NicClusterPolicy
   ```

5. **Deploy Network Definitions (Optional)**
   ```bash
   # Apply example MacvlanNetwork
   kubectl apply -f example/crs/mellanox.com_v1alpha1_macvlannetwork_cr.yaml
   
   # Verify network attachment definition
   kubectl get network-attachment-definitions -A
   ```

6. **Clean Up**
   ```bash
   # Uninstall the operator (this will preserve CRDs by default)
   helm uninstall -n nvidia-network-operator nvidia-network-operator
   
   # Optionally delete CRDs if you want to remove them
   kubectl delete crd nicclusterpolicies.mellanox.com
   kubectl delete crd macvlannetworks.mellanox.com
   kubectl delete crd hostdevicenetworks.mellanox.com
   kubectl delete crd network-attachment-definitions.k8s.cni.cncf.io
   
   # Delete the namespace
   kubectl delete namespace nvidia-network-operator
   
   # Delete the kind cluster
   kind delete cluster --name netop-test
   ```

### Advanced Component Testing in kind

While kind cannot test actual RDMA/hardware functionality, we can still test and understand many important components of the network operator:

#### 1. Testing Custom Resource Definitions (CRDs)

```bash
# List all CRDs installed by the operator
kubectl get crds | grep mellanox

# Examine CRD structures
kubectl explain NicClusterPolicy
kubectl explain MacvlanNetwork
kubectl explain HostDeviceNetwork
```

#### 2. Testing Operator Reconciliation

Create a test policy with deliberately incorrect settings to observe the operator's behavior:

```yaml
# test-policy-invalid.yaml
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: test-policy-invalid
spec:
  ofedDriver:
    image: nvcr.io/nvidia/mellanox/driver
    repository: nvcr.io/nvidia/mellanox
    version: invalid-version  # Invalid version to test error handling
```

Apply and observe:
```bash
kubectl apply -f test-policy-invalid.yaml
kubectl describe NicClusterPolicy test-policy-invalid
kubectl logs -n nvidia-network-operator deploy/network-operator
```

#### 3. Testing State Machine Transitions

Create a series of policy updates to test state transitions:

```bash
# 1. Create initial policy
kubectl apply -f config/samples/nic-cluster-policy.yaml

# 2. Watch operator logs in a separate terminal
kubectl logs -n nvidia-network-operator deploy/network-operator -f

# 3. Apply updates in sequence
kubectl patch NicClusterPolicy nic-cluster-policy --type merge \
  -p '{"spec":{"ofedDriver":{"version":"5.4-3.1.0.0"}}}'
```

#### 4. Testing Network Configurations

Test different network configurations (even without real hardware):

```yaml
# test-network-config.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: test-network
  namespace: default
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "eth0",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.1.0/24",
      "rangeStart": "192.168.1.200",
      "rangeEnd": "192.168.1.216"
    }
  }'
```

#### 5. Testing Operator Metrics

If metrics are enabled:

```bash
# Port-forward the metrics endpoint
kubectl port-forward -n nvidia-network-operator deploy/network-operator 8443:8443

# In another terminal, query metrics
curl -k https://localhost:8443/metrics
```

#### 6. Multi-node Testing

Create a multi-node kind cluster to better understand component interactions:

```bash
# Create multi-node kind configuration
cat <<EOF > kind-multi-node.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Create cluster
kind create cluster --config kind-multi-node.yaml --name netop-test-multi

# Enable debug logging in operator
kubectl patch deployment -n nvidia-network-operator network-operator \
  --type json \
  -p '[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LOG_LEVEL", "value": "debug"}}]'

# Monitor components
watch -n 1 'kubectl get pods,NicClusterPolicy,MacvlanNetwork -A'
```

#### Testing Best Practices

1. **Start Small**
   - Begin with minimal configurations
   - Add components one at a time
   - Document behavior changes

2. **Use Labels and Annotations**
   - Label test resources for easy cleanup
   - Use annotations to track test cases

3. **Monitor Multiple Components**
   - Use multiple terminal windows to watch different components
   - Consider using k9s for better visibility

4. **Clean Up Between Tests**
   ```bash
   # Clean up all test resources
   kubectl delete NicClusterPolicy --all
   kubectl delete NetworkAttachmentDefinition --all
   kind delete cluster --name netop-test-multi
   ```

## Cloud Testing Options

### Option 1: Azure (Most Common)

### Prerequisites for Azure
- Azure CLI installed and configured
  ```bash
  # Install Azure CLI
  brew install azure-cli  # For macOS
  # or
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  # For Ubuntu/Debian

  # Login to Azure
  az login

  # Verify subscription
  az account show
  ```
- Azure subscription with permissions to create resources
  - You need "Contributor" role or higher
  - Check quota for NC-series VMs in your desired region
- Kubernetes knowledge (for troubleshooting)
- Basic understanding of InfiniBand/RDMA networking

### Step-by-Step Azure Testing

1. **Configure Azure Environment**
   ```bash
   # Set variables
   RESOURCE_GROUP="netop-test-rg"
   LOCATION="eastus"        # Make sure this region has NC-series VMs
   CLUSTER_NAME="netop-cluster"
   VM_SIZE="Standard_NC6s_v3"  # Minimum size with Mellanox NICs

   # Verify VM size availability
   az vm list-sizes --location $LOCATION | grep $VM_SIZE

   # Create resource group
   az group create --name $RESOURCE_GROUP --location $LOCATION
   ```

2. **Create Virtual Network (Required for RDMA)**
   ```bash
   # Create VNet and Subnet
   az network vnet create \
     --resource-group $RESOURCE_GROUP \
     --name netop-vnet \
     --address-prefix 10.0.0.0/16 \
     --subnet-name netop-subnet \
     --subnet-prefix 10.0.1.0/24

   # Enable accelerated networking
   SUBNET_ID=$(az network vnet subnet show \
     --resource-group $RESOURCE_GROUP \
     --vnet-name netop-vnet \
     --name netop-subnet \
     --query id -o tsv)
   ```

3. **Create Virtual Machine Scale Set (VMSS)**
   ```bash
   # Create VMSS with ND series VMs (has Mellanox NICs)
   az vmss create \
     --resource-group $RESOURCE_GROUP \
     --name netop-vmss \
     --image UbuntuLTS \
     --vm-sku $VM_SIZE \
     --instance-count 2 \
     --generate-ssh-keys \
     --subnet $SUBNET_ID \
     --accelerated-networking true

   # Get the public IP of the first instance
   INSTANCE_IP=$(az vmss list-instance-public-ips \
     --resource-group $RESOURCE_GROUP \
     --name netop-vmss \
     --query "[0].ipAddress" -o tsv)

   # SSH into the instance
   ssh azureuser@$INSTANCE_IP
   ```

4. **Install Kubernetes on VMs**
   ```bash
   # SSH into each VM and run:
   curl -sfL https://get.k3s.io | sh -

   # Or for kubeadm:
   curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
   sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
   sudo apt-get update
   sudo apt-get install -y kubelet kubeadm kubectl
   ```

5. **Install NVIDIA Drivers and OFED**
   ```bash
   # Download MLNX_OFED
   wget https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.1.0.0/MLNX_OFED_LINUX-5.4-3.1.0.0-ubuntu20.04-x86_64.tgz

   # Extract and install
   tar xzf MLNX_OFED_LINUX-5.4-3.1.0.0-ubuntu20.04-x86_64.tgz
   cd MLNX_OFED_LINUX-5.4-3.1.0.0-ubuntu20.04-x86_64
   sudo ./mlnxofedinstall --force

   # Verify installation
   sudo ibstat
   ```

6. **Deploy Network Operator**
   ```bash
   # Apply operator manifests
   kubectl apply -k deployments/kustomization/base

   # Verify deployment
   kubectl get pods -n nvidia-network-operator
   ```

7. **Configure NicClusterPolicy**
   Create a file named `nic-policy.yaml`:
   ```yaml
   apiVersion: mellanox.com/v1alpha1
   kind: NicClusterPolicy
   metadata:
     name: nic-cluster-policy
   spec:
     ofedDriver:
       image: nvcr.io/nvidia/mellanox/driver
       repository: nvcr.io/nvidia/mellanox
       version: 5.4-3.1.0.0
     rdmaSharedDevicePlugin:
       image: nvcr.io/nvidia/cloud-native/k8s-rdma-shared-dev-plugin
       repository: nvcr.io/nvidia/cloud-native
       version: v1.2.1
     sriovDevicePlugin:
       image: nvcr.io/nvidia/cloud-native/k8s-sriov-device-plugin
       repository: nvcr.io/nvidia/cloud-native
       version: v3.5.1
   ```

   Apply the policy:
   ```bash
   kubectl apply -f nic-policy.yaml
   ```

8. **Validate Hardware Configuration**
   ```bash
   # Check RDMA devices
   kubectl get pods -n nvidia-network-operator
   kubectl describe node | grep nvidia.com/gpu

   # Test with a sample RDMA-aware pod
   kubectl apply -f examples/rdma-test-pod.yaml
   ```

9. **Clean Up Cloud Resources**
   ```bash
   # Delete all resources
   az group delete --name $RESOURCE_GROUP --yes
   ```

### Option 2: Oracle Cloud Infrastructure (OCI) - Simpler Alternative

Oracle Cloud offers a more straightforward setup with their GPU shapes (BM.GPU.B4.8 or VM.GPU.B4.8) that come with Mellanox ConnectX-6 NICs. They also offer a generous free tier and simpler networking configuration.

#### Prerequisites for OCI
- OCI CLI installed and configured
  ```bash
  # Install OCI CLI
  bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

  # Configure CLI
  oci setup config
  ```
- OCI account with access to GPU shapes
- Kubernetes knowledge

#### Step-by-Step OCI Testing

1. **Create a Compute Instance**
   ```bash
   # Create a VM.GPU.B4.8 instance using OCI Console:
   # 1. Navigate to Compute > Instances
   # 2. Click "Create Instance"
   # 3. Select "VM.GPU.B4.8" shape
   # 4. Choose Oracle Linux 8 or Ubuntu 20.04
   # 5. Ensure RDMA networking is enabled
   ```

2. **Install Kubernetes**
   ```bash
   # SSH into the instance
   ssh opc@<instance-ip>

   # Install k3s (simpler option)
   curl -sfL https://get.k3s.io | sh -

   # Get kubeconfig
   sudo cat /etc/rancher/k3s/k3s.yaml
   ```

3. **Install NVIDIA Drivers and OFED**
   ```bash
   # GPU driver and CUDA will be pre-installed
   # Install only OFED
   wget https://content.mellanox.com/ofed/MLNX_OFED-5.4-3.1.0.0/MLNX_OFED_LINUX-5.4-3.1.0.0-ol8u6-x86_64.tgz
   tar xzf MLNX_OFED_LINUX-5.4-3.1.0.0-ol8u6-x86_64.tgz
   cd MLNX_OFED_LINUX-5.4-3.1.0.0-ol8u6-x86_64
   sudo ./mlnxofedinstall --force
   ```

4. **Deploy Network Operator**
   ```bash
   # Follow the same steps as Azure deployment
   kubectl apply -k deployments/kustomization/base
   ```

5. **Clean Up**
   ```bash
   # Simply terminate the instance from OCI Console
   # or using CLI:
   oci compute instance terminate --instance-id <instance-id>
   ```

### Option 3: Google Cloud Platform (GCP)

GCP also offers A2 VMs with NVIDIA GPUs and Mellanox NICs, but they're typically more expensive and have less consistent availability compared to Azure or OCI. The setup process is similar to Azure but requires different CLI commands.

## Cloud Provider Comparison

| Feature | Azure | OCI | GCP |
|---------|-------|-----|-----|
| Setup Complexity | High | Low | Medium |
| Cost | Medium | Low (Free Tier) | High |
| VM Availability | Good | Limited | Limited |
| RDMA Support | Yes | Yes | Yes |
| Documentation | Excellent | Good | Good |
| Network Config | Complex | Simple | Medium |

## Recommendations

1. **For Learning/Testing:**
   - Start with OCI if you're new to cloud providers
   - Free tier available
   - Simpler networking setup
   - Pre-configured GPU drivers

2. **For Production:**
   - Azure offers better enterprise support
   - More regions and VM types
   - Better integration with enterprise tools

3. **For Cost-Effective Scale:**
   - OCI for smaller deployments
   - Azure for larger, enterprise deployments
   - GCP if already using other Google services

## Troubleshooting

Common issues and solutions:

1. **Operator Pod Fails to Start**
   - Check logs: `kubectl logs -n nvidia-network-operator deploy/network-operator`
   - Verify RBAC permissions
   - Check if CRDs are properly installed

2. **Device Plugin Issues**
   - Verify driver installation: `ibstat`
   - Check device plugin logs
   - Ensure proper device visibility in nodes

3. **RDMA/SR-IOV Problems**
   - Verify OFED installation
   - Check kernel modules: `lsmod | grep mlx`
   - Verify PCI devices: `lspci | grep Mellanox`

## References

- [Network Operator GitHub](https://github.com/Mellanox/network-operator)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [Mellanox OFED Documentation](https://docs.nvidia.com/networking/display/OFEDv525400/)
- [Azure InfiniBand Documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/infini-band)
- [kind Documentation](https://kind.sigs.k8s.io/)
