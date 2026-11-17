#!/usr/bin/env bash
set -euo pipefail

: "${OCI_COMPARTMENT_ID:?Missing OCI_COMPARTMENT_ID}"
: "${OCI_SUBNET_ID:?Missing OCI_SUBNET_ID}"
: "${OCI_CLI_REGION:?Missing OCI_CLI_REGION}"
: "${OCI_SSH_PUBLIC_KEY:?Missing OCI_SSH_PUBLIC_KEY}"

INSTANCE_NAME="main-server"
SHAPE="VM.Standard.A1.Flex"
OCPUS="1"
MEMORY_GB="2"
CLOUD_INIT_FILE="cloud-init/ubuntu.yaml"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"
}

# Load the local API key when running outside GitHub Actions.
if [[ -z "${OCI_CLI_KEY_CONTENT:-}" && -n "${OCI_API_KEY_FILE:-}" ]]; then
    KEY_FILE="${OCI_API_KEY_FILE/#\~/$HOME}"
    export OCI_CLI_KEY_CONTENT
    OCI_CLI_KEY_CONTENT="$(cat "$KEY_FILE")"
fi

# Do not create another instance with the same display name.
EXISTING_INSTANCE="$(
    oci compute instance list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --all \
        --query 'data[0].id' \
        --raw-output 2>/dev/null || true
)"

if [[ -n "$EXISTING_INSTANCE" && "$EXISTING_INSTANCE" != "null" ]]; then
    log "Instance already exists: $EXISTING_INSTANCE"
    exit 0
fi

log "Looking for Ubuntu 24.04 image..."

IMAGE_ID="$(
    oci compute image list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --operating-system "Canonical Ubuntu" \
        --operating-system-version "24.04" \
        --shape "$SHAPE" \
        --sort-by TIMECREATED \
        --sort-order DESC \
        --all \
        --query 'data[0].id' \
        --raw-output
)"

if [[ -z "$IMAGE_ID" || "$IMAGE_ID" == "null" ]]; then
    log "ERROR: Compatible Ubuntu 24.04 image not found."
    exit 1
fi

USER_DATA="$(base64 < "$CLOUD_INIT_FILE" | tr -d '\n')"

mapfile -t AVAILABILITY_DOMAINS < <(
    oci iam availability-domain list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --query 'data[].name' \
        --raw-output
)

if [[ "${#AVAILABILITY_DOMAINS[@]}" -eq 0 ]]; then
    log "ERROR: No availability domains found."
    exit 1
fi

SSH_KEY_FILE="$(mktemp)"
METADATA_FILE="$(mktemp)"
RESULT_FILE="$(mktemp)"

trap 'rm -f "$SSH_KEY_FILE" "$METADATA_FILE" "$RESULT_FILE"' EXIT

printf '%s\n' "$OCI_SSH_PUBLIC_KEY" > "$SSH_KEY_FILE"

jq -n --arg user_data "$USER_DATA" \
    '{user_data: $user_data}' > "$METADATA_FILE"

for AD in "${AVAILABILITY_DOMAINS[@]}"; do
    log "Trying availability domain: $AD"

    if oci compute instance launch \
        --availability-domain "$AD" \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --shape "$SHAPE" \
        --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEMORY_GB}}" \
        --image-id "$IMAGE_ID" \
        --subnet-id "$OCI_SUBNET_ID" \
        --assign-public-ip true \
        --ssh-authorized-keys-file "$SSH_KEY_FILE" \
        --metadata "file://$METADATA_FILE" \
        > "$RESULT_FILE" 2>&1; then

        INSTANCE_ID="$(jq -r '.data.id // empty' "$RESULT_FILE")"
        log "SUCCESS: Instance creation request accepted."
        log "Availability domain: $AD"
        log "Instance OCID: $INSTANCE_ID"
        exit 0
    fi

    ERROR_TEXT="$(cat "$RESULT_FILE")"

    if echo "$ERROR_TEXT" | grep -Eiq \
        "out of host capacity|out of capacity|capacity.*not available|not enough capacity"; then
        log "No A1 capacity in $AD. Trying the next domain..."
        continue
    fi

    log "ERROR: Instance launch failed."
    echo "$ERROR_TEXT"
    exit 1
done

log "No A1 capacity was available in the listed availability domains."
exit 2
