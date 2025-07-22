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
brew install docker  # Or Docker Desktop

# Verify installations
kind --version
kubectl version
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

3. **Deploy NVIDIA Device Plugin (Optional)**
   ```bash
   # This won't find real devices in kind but helps test integration
   kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml
   
   # Verify the plugin deployment
   kubectl get pods -n kube-system | grep nvidia
   ```

4. **Deploy the Network Operator**
   ```bash
   # Using provided manifests
   kubectl apply -k deployments/kustomization/base
   
   # Alternative quick deployment
   kubectl apply -f https://raw.githubusercontent.com/Mellanox/network-operator/master/deploy/operator.yaml
   ```

5. **Verify Operator Components**
   ```bash
   # Check operator pods
   kubectl get pods -n nvidia-network-operator
   
   # Check Custom Resource Definitions
   kubectl get crds | grep mellanox
   
   # Check operator logs
   kubectl logs -n nvidia-network-operator deploy/network-operator
   ```

6. **Create and Test Custom Resources**
   ```bash
   # Apply sample NicClusterPolicy
   kubectl apply -f config/samples/nic-cluster-policy.yaml
   
   # Check status
   kubectl get NicClusterPolicy -A
   kubectl describe NicClusterPolicy
   ```

7. **Clean Up Local Environment**
   ```bash
   # Delete the kind cluster
   kind delete cluster --name netop-test
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