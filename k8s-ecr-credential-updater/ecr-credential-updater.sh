#!/bin/bash
set -euo pipefail

# Use standard AWS-CLI environment variables to configure AWS parameters:
#   AWS_DEFAULT_REGION    - Set Default AWS region
#   AWS_ACCESS_KEY_ID     - (optional) Access key id, don't set it if you want to use instance profile
#   AWS_SECRET_ACCESS_KEY - (optional) Secret access key, don't set it if you want to use instance profile

# Registry secret related parameters
#   AWS_REGISTRY_REGIONS - space separated list of REGIONS to create secrets for,
#                         "self" means using AWS_DEFAULT_REGION
#   AWS_REGISTRY_IDS     - space separated list of registry (account ids), format ID[:REGION]
#                          add ":REGION" for region specific secret, using "self" if not specified, REGION should be listed also in AWS_REGISTRY_REGIONS
#
# For example, if assuming 123456789012 as self account id:
# Defaults:
#   AWS_DEFAULT_REGION="eu-central-1"
#   AWS_REGISTRY_REGIONS="self"
#   AWS_REGISTRY_IDS="self"
#   -> generates a single secret with single registry id:
#      ecr-credential-self:
#       - 123456789012.dkr.ecr.eu-central-1.amazonaws.com
#
# Multiple Registries in different regions:
#   AWS_DEFAULT_REGION="eu-central-1"
#   AWS_REGISTRY_REGIONS="self us-west-2"
#   AWS_REGISTRY_IDS="self 602401143452:us-west-2"
#   -> generates a 2 secrets with multiple registry id:
#      ecr-credential-self:
#       - 123456789012.dkr.ecr.eu-central-1.amazonaws.com
#      ecr-credential-us-west-2:
#       - 123456789012.dkr.ecr.us-west-2.amazonaws.com
#       - 602401143452.dkr.ecr.us-west-2.amazonaws.com

# Default values
export AWS_REGISTRY_REGIONS="${AWS_REGISTRY_REGIONS:-self}"
export AWS_REGISTRY_IDS="${AWS_REGISTRY_IDS:-self}"
export TARGET_NAMESPACES="${TARGET_NAMESPACE:-kube-system default}"
export ECR_CREDENTIALS_SECRETNAME_PREFIX="${ECR_CREDENTIALS_SECRETNAME_PREFIX:-ecr-credentials}"
export SERVICE_ACCOUNT_ACTION="${SERVICE_ACCOUNT:-patch}"
export SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-default}"

main() {
    # Temporary file for the secret
    ECR_SECRET_DIR=$(mktemp -d /tmp/ecr.XXXXXXXX)
        
    # Get credentials from AWS ECR API
    for REGION in ${AWS_REGISTRY_REGIONS}; do
        REGION_REGISTRY_IDS=""
        for REGISTRY in ${AWS_REGISTRY_IDS}; do
            REGISTRY_ID="$(echo ${REGISTRY} | cut -f1 -d:)"
            REGISTRY_REGION="$(echo ${REGISTRY} | cut -f2 -d:)"
            REGISTRY_REGION="${REGISTRY_REGION:-self}"

            if [ "${REGISTRY_ID}" == "self" ] ; then
                REGISTRY_ID="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .accountId)"
            fi

            if [ "${REGISTRY_REGION}" == "${REGION}" ]; then
                REGION_REGISTRY_IDS="${REGION_REGISTRY_IDS} ${REGISTRY_ID}"
            fi
        done

        log "Requesting ECR token with aws-cli for ${REGION} region with ids: [${REGION_REGISTRY_IDS}]..."
        request_credential "${REGION}" "${REGION_REGISTRY_IDS}" > "${ECR_SECRET_DIR}/${REGION}"
    done

    # Update Kubernetes secrets in each target namespace
    for NS in ${TARGET_NAMESPACES}; do
        for REGION in ${AWS_REGISTRY_REGIONS}; do
            # Create or update Kubernetes secret
            apply_secret "${NS}" "${REGION}"
        done

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
    REGION="${1:-self}"
    REGISTRY_IDS="${2}"
    if [ "${REGION}" != "self" -a "${REGION}" != "" ] ; then
        export AWS_DEFAULT_REGION="${REGION}"
    fi

    aws ecr get-authorization-token --registry-ids ${REGISTRY_IDS} \
    | jq '[ .authorizationData[] | { "key": (.proxyEndpoint), "value": { "auth": (.authorizationToken) } } ] | { "auths": (from_entries) }'
}

apply_secret() {
    NS="${1}"
    REGION="${2}"

    log "Applying secret in namespace ${NS}..."
    kubectl -n "${NS}" create secret generic \
        --dry-run=client -o yaml \
        --type=kubernetes.io/dockerconfigjson \
        --from-file=.dockerconfigjson="${ECR_SECRET_DIR}/${REGION}" \
        "${ECR_CREDENTIALS_SECRETNAME_PREFIX}-${REGION}" \
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
    PATCH_JSON='{"imagePullSecrets": []}'
    for REGION in ${AWS_REGISTRY_REGIONS}; do
        PATCH_JSON=$(jq ".imagePullSecrets |= . + [{\"name\": \"${ECR_CREDENTIALS_SECRETNAME_PREFIX}-${REGION}\"}]" <<< "${PATCH_JSON}")
    done
    log "Patching service-account \"${SERVICE_ACCOUNT}\" in namespace ${NS}..."
    kubectl -n "${NS}" patch serviceaccount "${SERVICE_ACCOUNT}" -p "${PATCH_JSON}"
}

log() {
    echo "[$(date +"%Y.%m.%d-%H:%M:%S")] $*"
}

main
