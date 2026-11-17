
#!/usr/bin/env bash

set -Eeuo pipefail

# ---------------------------------------
# Configuration
# ---------------------------------------

: "${OCI_COMPARTMENT_ID:?Missing OCI_COMPARTMENT_ID}"
: "${OCI_SUBNET_ID:?Missing OCI_SUBNET_ID}"
: "${OCI_CLI_REGION:?Missing OCI_CLI_REGION}"
: "${OCI_SSH_PUBLIC_KEY:?Missing OCI_SSH_PUBLIC_KEY}"

INSTANCE_NAME="${INSTANCE_NAME:-main-server}"

SHAPE="${OCI_SHAPE:-VM.Standard.A1.Flex}"
OCPUS="${OCI_OCPUS:-1}"
MEMORY_GB="${OCI_MEMORY_GB:-2}"
ASSIGN_PUBLIC_IP="${OCI_ASSIGN_PUBLIC_IP:-false}"

CLOUD_INIT_FILE="cloud-init/ubuntu.yaml"

log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"
}

# ---------------------------------------
# Check OCI CLI
# ---------------------------------------

if ! command -v oci >/dev/null 2>&1; then
    log "ERROR: OCI CLI is not installed."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log "ERROR: jq is not installed."
    exit 1
fi

# ---------------------------------------
# Validate resource configuration
# ---------------------------------------

if ! [[ "$OCPUS" =~ ^[0-9]+$ ]] ||
   ! [[ "$MEMORY_GB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    log "ERROR: Invalid CPU or memory configuration."
    exit 1
fi

if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
    log "ERROR: Cloud-init file not found."
    exit 1
fi

# ---------------------------------------
# Check existing instance
# ---------------------------------------

log "Checking for existing instance: $INSTANCE_NAME"

INSTANCE_LIST="$(
    oci compute instance list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --all \
        --output json
)"

EXISTING_INSTANCE="$(
    jq -r --arg name "$INSTANCE_NAME" '
        [
          .data[]
          | select(."display-name" == $name)
          | select(."lifecycle-state" != "TERMINATED")
        ][0].id // empty
    ' <<< "$INSTANCE_LIST"
)"

if [[ -n "$EXISTING_INSTANCE" ]]; then
    log "Instance already exists."
    log "Instance OCID: $EXISTING_INSTANCE"
    exit 0
fi

# ---------------------------------------
# Find Ubuntu 24.04 image
# ---------------------------------------

log "Finding Ubuntu 24.04 image for $SHAPE..."

IMAGE_LIST="$(
    oci compute image list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --operating-system "Canonical Ubuntu" \
        --operating-system-version "24.04" \
        --shape "$SHAPE" \
        --sort-by TIMECREATED \
        --sort-order DESC \
        --all \
        --output json
)"

IMAGE_ID="$(
    jq -r '
        [.data[] | select(."lifecycle-state" == "AVAILABLE")]
        | sort_by(."time-created")
        | last.id // empty
    ' <<< "$IMAGE_LIST"
)"

if [[ -z "$IMAGE_ID" ]]; then
    log "ERROR: Compatible Ubuntu 24.04 image not found."
    exit 1
fi

log "Selected image: $IMAGE_ID"

# ---------------------------------------
# Retrieve availability domains
# ---------------------------------------

log "Retrieving availability domains..."

AD_LIST="$(
    oci iam availability-domain list \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --output json
)"

mapfile -t AVAILABILITY_DOMAINS < <(
    jq -r '.data[].name' <<< "$AD_LIST"
)

if [[ "${#AVAILABILITY_DOMAINS[@]}" -eq 0 ]]; then
    log "ERROR: No availability domains found."
    exit 1
fi

# ---------------------------------------
# Prepare cloud-init and SSH key
# ---------------------------------------

USER_DATA="$(
    base64 < "$CLOUD_INIT_FILE" | tr -d '\n'
)"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

SSH_KEY_FILE="$TEMP_DIR/ssh_key.pub"
METADATA_FILE="$TEMP_DIR/metadata.json"
RESULT_FILE="$TEMP_DIR/result.json"

printf '%s\n' "$OCI_SSH_PUBLIC_KEY" > "$SSH_KEY_FILE"

jq -n --arg user_data "$USER_DATA" \
    '{user_data: $user_data}' > "$METADATA_FILE"

# ---------------------------------------
# Try each availability domain
# ---------------------------------------

for AD in "${AVAILABILITY_DOMAINS[@]}"; do

    log "Attempting provisioning in: $AD"

    if oci compute instance launch \
        --availability-domain "$AD" \
        --compartment-id "$OCI_COMPARTMENT_ID" \
        --display-name "$INSTANCE_NAME" \
        --shape "$SHAPE" \
        --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEMORY_GB}}" \
        --image-id "$IMAGE_ID" \
        --subnet-id "$OCI_SUBNET_ID" \
        --assign-public-ip "$ASSIGN_PUBLIC_IP" \
        --ssh-authorized-keys-file "$SSH_KEY_FILE" \
        --metadata "file://$METADATA_FILE" \
        --output json \
        > "$RESULT_FILE" 2>&1; then

        INSTANCE_ID="$(jq -r '.data.id // empty' "$RESULT_FILE")"

        log "SUCCESS: Instance launch request accepted."
        log "Availability domain: $AD"
        log "Instance OCID: $INSTANCE_ID"

        exit 0
    fi

    ERROR_TEXT="$(cat "$RESULT_FILE")"

    if grep -Eiq \
        "out of host capacity|out of capacity|capacity.*not available|not enough capacity" \
        <<< "$ERROR_TEXT"; then

        log "No capacity available in $AD."
        log "Trying next availability domain..."
        continue
    fi

    log "ERROR: Instance launch failed."
    echo "$ERROR_TEXT"
    exit 1

done

log "No A1 capacity available in the listed availability domains."
log "The next scheduled workflow will retry."

exit 2
