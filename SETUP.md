# TAP GitOps Setup with Vault and Kind on Colima

This guide walks you through setting up Tanzu Application Platform (TAP) using GitOps with External Secrets Operator (ESO) and HashiCorp Vault, running on a kind cluster within a Colima VM.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Colima VM                            │
│                                                         │
│  ┌──────────────┐           ┌──────────────┐            │
│  │  Vault       │◄────────► │  Kind        │            │
│  │  Container   │  Docker   │  Cluster     │            │
│  │  :8200       │  Network  │  (tap)       │            │
│  └──────────────┘           └──────────────┘            │
│         │                        │                      │
│         └────────────────────────┘                      │
│              Docker Bridge Network                      │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Colima VM** running with Docker daemon
- **Docker CLI** configured to use Colima
- **kubectl** installed
- **kind** installed (`brew install kind` on macOS)
- **tappr** installed (for installing cluster essentials - kapp-controller, secretgen-controller)
- **vault CLI** installed (optional, for manual operations)
- **kapp** and **ytt** installed (for Tanzu Sync deployment)
- **Access to VMware Tanzu Network** registry (for TAP packages)
- **jq** installed (optional, for JSON processing in scripts)

## Quick Start

### Option 1: Automated Setup (Recommended)

Run the master setup script that orchestrates all steps:

```bash
export INSTALL_REGISTRY_USERNAME="<your-tanzu-network-username>"
export INSTALL_REGISTRY_PASSWORD="<your-tanzu-network-password>"
export CLUSTER_NAME="tap-iterate"
export TAP_VERSION="1.12.6-build.13"
# Optional: Specify custom TAP package repository (default: registry.tanzu.vmware.com/tanzu-application-platform/tap-packages)
export TAP_PKGR_REPO="registry.tanzu.vmware.com/tanzu-application-platform/tap-packages"
# Optional: Specify registry hostname (default: registry.tanzu.vmware.com)
export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"
# Optional: Path to TAP non-sensitive values file
export TAP_VALUES_FILE="/path/to/your-tap-values.yaml"

./scripts/setup-tap-gitops.sh
```

### Option 2: Manual Step-by-Step Setup

Follow the steps below for more control over each phase.

## Step-by-Step Setup

### Phase 1: Vault Setup

#### 1.1 Start Vault Container

```bash
./scripts/setup-vault.sh
```

This script:
- Creates a Vault container in dev mode (auto-unsealed, suitable for local development)
- Exposes Vault on port 8200
- Configures Vault to be accessible from kind cluster

**Environment Variables:**
- `VAULT_CONTAINER_NAME` - Name for Vault container (default: `vault-tap`)
- `VAULT_PORT` - Port to expose Vault on (default: `8200`)
- `VAULT_DEV_MODE` - Run in dev mode (default: `true`)
- `VAULT_IMAGE` - Vault Docker image (default: `hashicorp/vault:1.15.2`)

**Output:**
The script will display the Vault container IP and address. Note these for later use.

#### 1.2 Verify Vault is Running

```bash
docker ps | grep vault-tap
curl http://localhost:8200/v1/sys/health
```

### Phase 2: Kind Cluster Setup

#### 2.1 Create Kind Cluster

```bash
./scripts/create-kind-cluster.sh
```

This script:
- Creates a kind cluster named `tap-iterate`
- Configures networking for access to Docker containers
- Sets up port mappings for ingress

**Environment Variables:**
- `CLUSTER_NAME` - Name of the kind cluster (default: `tap-iterate`)
- `KIND_CONFIG_FILE` - Path to kind config file (default: `kind-config.yaml`)

#### 2.2 Install Cluster Essentials

After creating the kind cluster, install the required controllers for TAP:

```bash
tappr tap install-cluster-essentials
```

This installs the required controllers (kapp-controller, secretgen-controller) needed for TAP installation.

**Note:** If `tappr` is not installed, you can install it or install cluster essentials manually. See [Tanzu Application Platform documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/) for manual installation steps.

#### 2.3 Verify Cluster

```bash
kubectl cluster-info --context kind-tap-iterate
kubectl get nodes
kubectl get pods -n kapp-controller
kubectl get pods -n secretgen-controller
```

### Phase 3: Network Connectivity Test

#### 3.1 Test Vault Connectivity from Kind

```bash
./scripts/vault-network-test.sh
```

This script:
- Creates a test pod in the kind cluster
- Tests connectivity to Vault container
- Verifies network configuration

**Environment Variables:**
- `VAULT_CONTAINER_NAME` - Name of Vault container (default: `vault-tap`)
- `CLUSTER_NAME` - Name of kind cluster (default: `tap-iterate`)

### Phase 4: Vault Configuration

#### 4.1 Get Vault Container IP

```bash
VAULT_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vault-tap)
export VAULT_ADDR="http://${VAULT_IP}:8200"
export VAULT_TOKEN="root-token"  # For dev mode
export CLUSTER_NAME="tap-iterate"
```

#### 4.2 Enable Kubernetes Authentication

```bash
cd clusters/tap-iterate
tanzu-sync/scripts/setup/create-kubernetes-auth.sh
```

This configures Vault to authenticate using Kubernetes service account tokens.

#### 4.3 Create Vault Policies

```bash
tanzu-sync/scripts/setup/create-policies.sh
```

This creates policies for:
- Tanzu Sync secrets: `secret/dev/tap-iterate/tanzu-sync/*`
- TAP install secrets: `secret/dev/tap-iterate/tap/*`

#### 4.4 Create Vault Roles

```bash
tanzu-sync/scripts/setup/create-roles.sh
```

This creates roles bound to:
- `tanzu-sync-vault-sa` service account in `tanzu-sync` namespace
- `tap-install-vault-sa` service account in `tap-install` namespace

### Phase 5: Populate Vault Secrets

#### 5.1 Store Secrets in Vault

```bash
export INSTALL_REGISTRY_USERNAME="<your-username>"
export INSTALL_REGISTRY_PASSWORD="<your-password>"
export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"

./scripts/setup-vault-secrets.sh
```

This stores:
- Registry credentials at `secret/data/dev/tap-iterate/tanzu-sync/install-registry-dockerconfig`
- TAP sensitive values at `secret/data/dev/tap-iterate/tap/sensitive-values.yaml` (creates empty secret if not provided)

**Important:** Per [official TAP documentation](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-application-platform/1-12/tap/install-gitops-eso-hashicorp-vault.html), Vault does not support storing YAML files directly. All secrets must be in key-value format. The script automatically converts YAML content to a key-value pair where the key is `sensitive_tap_values_yaml` and the value is the YAML content as a string.

**Optional:**
- `TAP_SENSITIVE_VALUES_FILE` - Path to TAP sensitive values YAML file (if not provided, an empty secret is created)
- `GIT_USERNAME` and `GIT_PASSWORD` - Git credentials for Tanzu Sync

**Note:** When moving sensitive values from `tap-values.yaml` to Vault, omit the `tap_install.values` root but keep the remaining structure. For example:
- In `tap-values.yaml`: `tap_install.values.ootb_supply_chain_basic.gitops.ssh_secret`
- In Vault secret: `ootb_supply_chain_basic.gitops.ssh_secret`

### Phase 6: Kubernetes RBAC Setup

#### 6.1 Apply Service Accounts and RBAC

```bash
cd clusters/tap-iterate
kubectl apply -f tanzu-sync/bootstrap/vault-rbac-tanzu-sync.yaml
kubectl apply -f tanzu-sync/bootstrap/vault-rbac-tap-install.yaml
```

These resources create:
- Service accounts for Vault authentication
- ClusterRoleBindings for token review permissions

### Phase 7: Configure Tanzu Sync

#### 7.1 Configure Tanzu Sync

```bash
cd clusters/tap-iterate
# Optional: Specify custom TAP package repository
export TAP_PKGR_REPO="registry.tanzu.vmware.com/tanzu-application-platform/tap-packages"
tanzu-sync/scripts/configure.sh
```

This creates:
- `tanzu-sync/app/values/tanzu-sync.yaml` - Git repo configuration
- `cluster-config/values/tap-install-values.yaml` - TAP install configuration

**Note:** The `configure.sh` script uses `TAP_PKGR_REPO` environment variable (default: `registry.tanzu.vmware.com/tanzu-application-platform/tap-packages`) to set the package repository. For air-gapped installations, set this to your internal registry mirror.

#### 7.2 Configure Vault Secrets

```bash
export VAULT_ADDR="http://<vault-ip>:8200"
export CLUSTER_NAME="tap-iterate"
tanzu-sync/scripts/configure-secrets.sh
```

This creates:
- `tanzu-sync/app/values/tanzu-sync-vault-values.yaml` - ESO configuration for Tanzu Sync
- `cluster-config/values/tap-install-vault-values.yaml` - ESO configuration for TAP install

#### 7.3 Configure TAP Non-Sensitive Values

If you have custom TAP values (non-sensitive), you can configure them:

```bash
# Option 1: Use the configure script
export TAP_VALUES_FILE="/path/to/your-tap-values.yaml"
./scripts/configure-tap-values.sh -f "${TAP_VALUES_FILE}"

# Option 2: Edit the file directly
# Edit: clusters/tap-iterate/cluster-config/values/tap-install-values.yaml
```

**TAP Values File Structure:**
```yaml
tap_install:
  values:
    shared:
      ingress_domain: "example.com"
    ceip_policy_disclosed: true
    # ... other TAP configuration
```

**Note:** Sensitive values should be stored in Vault (see Phase 5.1), not in this file.

#### 7.4 Update TAP Version

```bash
export TAP_VERSION="1.12.6-build.13"
./scripts/update-tap-version.sh
```

This updates TAP version in configuration files.

### Phase 8: Bootstrap Tanzu Sync

#### 8.1 Bootstrap with Registry Credentials

```bash
cd clusters/tap-iterate
export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"  # Or your custom registry
export INSTALL_REGISTRY_USERNAME="<your-username>"
export INSTALL_REGISTRY_PASSWORD="<your-password>"

tanzu-sync/scripts/bootstrap.sh
```

This applies bootstrap resources including registry credentials.

**Note:** `INSTALL_REGISTRY_HOSTNAME` should match the registry where TAP packages are stored. For VMware Tanzu Network, use `registry.tanzu.vmware.com`. For air-gapped installations, use your internal registry hostname.

### Phase 9: Deploy Tanzu Sync

#### 9.1 Deploy Tanzu Sync

```bash
cd clusters/tap-iterate
tanzu-sync/scripts/deploy.sh
```

This deploys:
- Tanzu Sync components
- External Secrets Operator
- SecretStore and ExternalSecret resources

#### 9.2 Verify Deployment

```bash
# Check Tanzu Sync pods
kubectl get pods -n tanzu-sync

# Check External Secrets Operator
kubectl get pods -n external-secrets-system

# Check ExternalSecret resources
kubectl get externalsecret -n tanzu-sync
kubectl get externalsecret -n tap-install

# Check secret sync status
kubectl describe externalsecret -n tanzu-sync
```

### Phase 10: Monitor TAP Installation

#### 10.1 Monitor Package Installation

```bash
# Check PackageRepository
kubectl get packagerepository -n tap-install

# Check PackageInstall
kubectl get packageinstall -n tap-install

# Watch TAP installation
kubectl get packageinstall tap -n tap-install -w

# Check TAP components
kubectl get pods -A | grep tap
```

## Environment Variables Summary

```bash
# Vault Configuration
export VAULT_ADDR="http://<vault-ip>:8200"
export VAULT_TOKEN="root-token"  # For dev mode
export CLUSTER_NAME="tap-iterate"

# Registry Credentials
export INSTALL_REGISTRY_HOSTNAME="registry.tanzu.vmware.com"
export INSTALL_REGISTRY_USERNAME="<your-username>"
export INSTALL_REGISTRY_PASSWORD="<your-password>"

# TAP Configuration
export TAP_VERSION="1.12.6-build.13"
export TAP_PKGR_REPO="registry.tanzu.vmware.com/tanzu-application-platform/tap-packages"
export TAP_VALUES_FILE="/path/to/your-tap-values.yaml"  # Optional: Custom TAP values
```

**Notes:**
- `TAP_PKGR_REPO` specifies the OCI registry and repository path for the TAP PackageRepository. This is used by `configure.sh` to set the package repository in both Tanzu Sync and TAP install configurations. For air-gapped installations, set this to your internal registry mirror.
- `INSTALL_REGISTRY_HOSTNAME` is used for bootstrap (to fetch ESO package) and for storing registry credentials in Vault. Defaults to `registry.tanzu.vmware.com`.
- `TAP_VALUES_FILE` is optional and should point to a YAML file containing non-sensitive TAP configuration values under `tap_install.values`. Sensitive values should be stored in Vault.

## Troubleshooting

### Vault Connectivity Issues

**Problem:** Kind cluster cannot reach Vault container

**Solutions:**
1. Verify Vault container is running: `docker ps | grep vault-tap`
2. Get Vault IP: `docker inspect vault-tap | grep IPAddress`
3. Test from kind: `kubectl run test --image=curlimages/curl -it --rm -- curl http://<vault-ip>:8200/v1/sys/health`
4. Ensure both containers are on the same Docker network

### ESO Authentication Issues

**Problem:** External Secrets Operator cannot authenticate with Vault

**Solutions:**
1. Verify Kubernetes auth is enabled: `vault auth list`
2. Check service accounts exist: `kubectl get sa -n tanzu-sync tanzu-sync-vault-sa`
3. Verify roles are created: `vault list auth/tap-iterate/role`
4. Check ExternalSecret status: `kubectl describe externalsecret -n tanzu-sync`

### Secret Sync Issues

**Problem:** Secrets are not syncing from Vault

**Solutions:**
1. Verify secrets exist in Vault: `vault kv get secret/dev/tap-iterate/tanzu-sync/install-registry-dockerconfig`
2. Check Vault policies allow read: `vault policy read tap-iterate--read-tanzu-sync-secrets`
3. Verify SecretStore configuration: `kubectl get secretstore -n tanzu-sync -o yaml`
4. Check ESO logs: `kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets`

### TAP Installation Issues

**Problem:** TAP packages are not installing

**Solutions:**
1. Check PackageRepository status: `kubectl describe packagerepository -n tap-install`
2. Verify registry credentials are synced: `kubectl get secret -n tap-install`
3. Check PackageInstall events: `kubectl describe packageinstall tap -n tap-install`
4. Review TAP values: `kubectl get secret tap-values -n tap-install -o yaml`

## Cleanup

### Quick Cleanup (Recommended)

Use the master cleanup script to remove everything:

```bash
./scripts/cleanup-tap-gitops.sh
```

This will:
- Delete the kind cluster
- Stop and remove the Vault container
- Preserve Vault data and configuration files by default

### Advanced Cleanup Options

#### Remove Everything (Including Data and Config)

```bash
./scripts/cleanup-tap-gitops.sh --all
```

Or use the aggressive cleanup script:

```bash
./scripts/cleanup-all.sh
```

**Warning:** This removes all Vault data and generated configuration files!

#### Individual Cleanup Scripts

**Cleanup Vault only:**
```bash
# Remove Vault container (preserve data)
./scripts/cleanup-vault.sh

# Remove Vault container and data
./scripts/cleanup-vault.sh --remove-data
```

**Cleanup kind cluster only:**
```bash
./scripts/cleanup-kind-cluster.sh
```

**Cleanup with options:**
```bash
# Remove config files but keep Vault data
./scripts/cleanup-tap-gitops.sh --remove-config

# Remove Vault data but keep config files
./scripts/cleanup-tap-gitops.sh --remove-vault-data
```

### Manual Cleanup

If you prefer to clean up manually:

```bash
# Delete kind cluster
kind delete cluster --name tap-iterate

# Stop and remove Vault container
docker stop vault-tap
docker rm vault-tap

# Remove Vault data (if using persistent storage)
rm -rf ./vault-data

# Remove kubectl context (optional)
kubectl config delete-context kind-tap-iterate

# Remove generated configuration files (optional)
cd clusters/tap-iterate
rm -f tanzu-sync/app/values/tanzu-sync.yaml
rm -f tanzu-sync/app/values/tanzu-sync-vault-values.yaml
rm -f cluster-config/values/tap-install-values.yaml
rm -f cluster-config/values/tap-install-vault-values.yaml
```

## Additional Resources

- [Tanzu Application Platform Documentation](https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/)
- [External Secrets Operator Documentation](https://external-secrets.io/)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Kind Documentation](https://kind.sigs.k8s.io/)

## Scripts Reference

### Setup Scripts

- `scripts/setup-vault.sh` - Start Vault container
- `scripts/create-kind-cluster.sh` - Create kind cluster
- `scripts/vault-network-test.sh` - Test network connectivity
- `scripts/setup-vault-secrets.sh` - Populate Vault with secrets
- `scripts/configure-tap-values.sh` - Configure TAP non-sensitive values
- `scripts/update-tap-version.sh` - Update TAP version
- `scripts/setup-tap-gitops.sh` - Master setup script (orchestrates all steps)

### Cleanup Scripts

- `scripts/cleanup-vault.sh` - Remove Vault container (optionally remove data)
- `scripts/cleanup-kind-cluster.sh` - Delete kind cluster
- `scripts/cleanup-tap-gitops.sh` - Master cleanup script (orchestrates cleanup)
- `scripts/cleanup-all.sh` - Aggressive cleanup (removes everything including data and configs)

