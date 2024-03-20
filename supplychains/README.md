## Tanzu Supply Chains

This repo contains manifests for supplychains, components, rbac and required tekton resources for installing the supplychain package.

### Package details:
```
group: supplychains.tanzu.vmware.com
description: This is my first Supplychain group
```

## Install the Supply Chains on the cluster
```
# Install to the default namespace
make install

# Install to a specific (foo) namespace
NAMESPACE=foo make install
```

## Uninstall the Supply Chains from the cluster
```
# Uninstall from the default namespace
make uninstall

# Uninstall from a specific (foo) namespace
NAMESPACE=foo make uninstall
```