# Vault configuration for production mode
# This file is used when VAULT_DEV_MODE=false

ui = true

storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

# For production, you should enable TLS
# listener "tcp" {
#   address       = "0.0.0.0:8200"
#   tls_cert_file = "/vault/certs/vault.crt"
#   tls_key_file  = "/vault/certs/vault.key"
# }

# Enable audit logging
# audit_device "file" {
#   path = "/vault/audit"
#   file_path = "audit.log"
# }

