#!/bin/bash
set -euo pipefail

# Use standard AWS environment variables to configure AWS parameters:
#   AWS_DEFAULT_REGION    - Set AWS region
#   AWS_ACCESS_KEY_ID     - (optional) Access key id, don't set it if you want to use instance profile
#   AWS_SECRET_ACCESS_KEY - (optional) Secret access key, don't set it if you want to use instance profile

# Default values
TARGET_NAMESPACES="${TARGET_NAMESPACE:-kube-system default}"
ECR_CREDENTIALS_SECRETNAME="${ECR_CREDENTIALS_SECRETNAME:-ecr-credentials}"
SERVICE_ACCOUNT_ACTION="${SERVICE_ACCOUNT:-patch}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-default}"

main() {
    # Temporary file for the secret
    ECR_SECRET_FILE=$(mktemp)
    
    # Get credentials from AWS ECR API
    request_credential > "${ECR_SECRET_FILE}"
    
    # Update Kubernetes secrets in each target namespace
    for NS in ${TARGET_NAMESPACES}; do
        # Create or update Kubernetes secret
        apply_secret "${NS}"

        # Manage the pullSecret for service account
        case "${SERVICE_ACCOUNT_ACTION}" in
            create)
                create_service_account ;; 
            patch)
                patch_service_account ;;
            *)
                log "No ServiceAccount action has been taken." ;; 
        esac
    done

    # Cleanup
    rm -f "${ECR_SECRET_FILE}"
}

request_credential() {
    log "Requesting ECR token with aws-cli..."
    aws ecr get-authorization-token \
    | jq '{"auths":{ (.authorizationData[0].proxyEndpoint) : {"auth": .authorizationData[0].authorizationToken}}}'
}

apply_secret() {
    NS="${1}"

    log "Applying secret in namespace ${NS}..."
    kubectl -n "${NS}" create secret generic \
        --dry-run=true -o yaml \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="${ECR_SECRET_FILE}" \
        "${ECR_CREDENTIALS_SECRETNAME}" \
    | kubectl -n "${NS}" apply -f -
}

patch_service_account() {
    NS="${1}"

    log "Patching service-account \"${SERVICE_ACCOUNT}\" in namespace ${NS}..."
    kubectl -n "${NS}" patch serviceaccount "${SERVICE_ACCOUNT}" \
        -p "{\"imagePullSecrets\": [{\"name\": \"${ECR_CREDENTIALS_SECRETNAME}\"}]}"
}

patch_service_account() {
    NS="${1}"

    log "Patching service-account \"${SERVICE_ACCOUNT}\" in namespace ${NS}..."
    kubectl -n "${NS}" patch serviceaccount "${SERVICE_ACCOUNT}" \
        -p "{\"imagePullSecrets\": [{\"name\": \"${ECR_CREDENTIALS_SECRETNAME}\"}]}"
}

log() {
    echo "[$(date +"%Y.%m.%d-%H:%M:%S")] $*"
}

main
