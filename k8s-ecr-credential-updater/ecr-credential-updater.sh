#!/bin/bash
set -euo pipefail

# Use standard AWS environment variables to configure AWS parameters:
#   AWS_DEFAULT_REGION    - Set AWS region
#   AWS_ACCESS_KEY_ID     - (optional) Access key id, don't set it if you want to use instance profile
#   AWS_SECRET_ACCESS_KEY - (optional) Secret access key, don't set it if you want to use instance profile

# Default values
export AWS_REGISTRY_ACCOUNT_IDS="${AWS_REGISTRY_ACCOUNT_IDS:-self}"
export TARGET_NAMESPACES="${TARGET_NAMESPACE:-kube-system default}"
export ECR_CREDENTIALS_SECRETNAME="${ECR_CREDENTIALS_SECRETNAME:-ecr-credentials}"
export SERVICE_ACCOUNT_ACTION="${SERVICE_ACCOUNT:-patch}"
export SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-default}"

main() {
    # Temporary file for the secret
    ECR_SECRET_FILE=$(mktemp)

    if [[ "${AWS_REGISTRY_ACCOUNT_IDS}" == *"self"* ]] ; then
        SELF_ACCOUNT_ID="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)"
        export AWS_REGISTRY_ACCOUNT_IDS="$(echo ${AWS_REGISTRY_ACCOUNT_IDS} | sed "s/self/${SELF_ACCOUNT_ID}/g")"
    fi
    # Get credentials from AWS ECR API
    log "Requesting ECR token with aws-cli..."
    request_credential > "${ECR_SECRET_FILE}"

    # Update Kubernetes secrets in each target namespace
    for NS in ${TARGET_NAMESPACES}; do
        # Create or update Kubernetes secret
        apply_secret "${NS}"

        # Manage the pullSecret for service account
        case "${SERVICE_ACCOUNT_ACTION}" in
            create)
                create_service_account "${NS}"
                patch_service_account "${NS}" ;;
            patch)
                patch_service_account "${NS}" ;;
            *)
                log "No ServiceAccount action has been taken." ;;
        esac
    done

    # Cleanup
    #rm -f "${ECR_SECRET_FILE}"
}

request_credential() {
    aws ecr get-authorization-token --registry-ids ${AWS_REGISTRY_ACCOUNT_IDS} \
    | jq '[ .authorizationData[] | { "key": (.proxyEndpoint), "value": { "auth": (.authorizationToken) } } ] | { "auths": (from_entries) }'
}

apply_secret() {
    NS="${1}"

    log "Applying secret in namespace ${NS}..."
    kubectl -n "${NS}" create secret generic \
        --dry-run=client -o yaml \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="${ECR_SECRET_FILE}" \
        "${ECR_CREDENTIALS_SECRETNAME}" \
    | kubectl -n "${NS}" apply -f -
}

create_service_account() {
    NS="${1}"

    log "Create service-account \"${SERVICE_ACCOUNT}\" in namespace ${NS}..."
    kubectl -n "${NS}" create serviceaccount --dry-run=client -o yaml "${SERVICE_ACCOUNT}" \
    | kubectl apply -f -
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
