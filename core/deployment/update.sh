#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

MODULE_ID="${1:-}"

if [[ -z "${MODULE_ID}" ]]; then
    die "Usage: $0 <module-id>"
fi

require_command docker

MODULE_DIR="$(require_module "${MODULE_ID}")"
COMPOSE_FILE="${MODULE_DIR}/compose.yml"

log_info "Checking module for updates: ${MODULE_ID}"
log_info "Module directory: ${MODULE_DIR}"

validate_metadata "${MODULE_DIR}"

check_dependencies "${MODULE_DIR}"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    die "Module compose file not found: ${COMPOSE_FILE}"
fi

log_info "Reading desired module images..."

mapfile -t DESIRED_IMAGES < <(
    docker compose \
        -f "${COMPOSE_FILE}" \
        config --images |
        sort -u
)

if [[ "${#DESIRED_IMAGES[@]}" -eq 0 ]]; then
    die "No deployment images were found in: ${COMPOSE_FILE}"
fi

missing_images=0

for image in "${DESIRED_IMAGES[@]}"; do
    if docker image inspect "${image}" >/dev/null 2>&1; then
        log_info "Required image is available: ${image}"
    else
        log_warn "Required image is missing: ${image}"
        missing_images=1
    fi
done

if (( missing_images )); then
    echo
    log_info "Pulling missing module images..."

    docker compose \
        -f "${COMPOSE_FILE}" \
        pull --policy missing

    echo
fi

log_info "Comparing running deployment with desired images..."

recreate_required=0

mapfile -t SERVICES < <(
    docker compose \
        -f "${COMPOSE_FILE}" \
        config --services
)

if [[ "${#SERVICES[@]}" -eq 0 ]]; then
    die "No services were found in: ${COMPOSE_FILE}"
fi

for service in "${SERVICES[@]}"; do
    container_id="$(
        docker compose \
            -f "${COMPOSE_FILE}" \
            ps -q "${service}"
    )"

    if [[ -z "${container_id}" ]]; then
        log_warn "Service is not currently running: ${service}"
        recreate_required=1
        break
    fi

    desired_image="$(
        docker compose \
            -f "${COMPOSE_FILE}" \
            config --format json |
        python3 -c '
import json
import sys

service = sys.argv[1]
config = json.load(sys.stdin)

image = config.get("services", {}).get(service, {}).get("image")

if image:
    print(image)
' "${service}"
    )"

    if [[ -z "${desired_image}" ]]; then
        log_warn "No image is configured for service: ${service}"
        recreate_required=1
        break
    fi

    desired_image_id="$(
        docker image inspect \
            --format '{{.Id}}' \
            "${desired_image}" \
            2>/dev/null || true
    )"

    if [[ -z "${desired_image_id}" ]]; then
        log_warn "Configured image is not available locally: ${desired_image}"
        recreate_required=1
        break
    fi

    running_image_id="$(
        docker inspect \
            --format '{{.Image}}' \
            "${container_id}"
    )"

    if [[ "${running_image_id}" != "${desired_image_id}" ]]; then
        log_info "Running image differs from configured image."
        echo "[DETAIL] Service: ${service}"
        echo "[DETAIL] Image: ${desired_image}"
        recreate_required=1
        break
    fi
done

if (( recreate_required == 0 )); then
    echo
    log_info "No update available."
    echo "[DETAIL] Module: ${MODULE_ID}"
    echo "[DETAIL] Running deployment already matches the configured images."

    run_healthcheck "${MODULE_DIR}"

    log_info "Module ${MODULE_ID} is current and healthy."
    exit 0
fi

echo
log_info "Deployment change required."
log_info "Recreating module with configured images..."

docker compose \
    -f "${COMPOSE_FILE}" \
    up -d

run_healthcheck "${MODULE_DIR}"

log_info "Module ${MODULE_ID} updated and healthy."
