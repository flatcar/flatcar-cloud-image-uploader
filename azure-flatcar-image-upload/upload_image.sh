#!/bin/bash

set -euo pipefail

# Default values
FLATCAR_LINUX_CHANNEL=stable
FLATCAR_LINUX_VERSION=current
LOCATION=westeurope
STORAGE_ACCOUNT_TYPE=Standard_LRS
HYPER_V_GEN=V2

usage() {
	cat <<HELP_USAGE
Usage: $0 [OPTION...]

 Required arguments:
  -g, --resource-group        Azure resource group.

 Optional arguments:
  -c, --channel              Flatcar Linux release channel. Defaults to '${FLATCAR_LINUX_CHANNEL}'.
  -v, --version              Flatcar Linux version. Defaults to '${FLATCAR_LINUX_VERSION}'.
  -i, --image-name           Image name, which will be used later in Lokomotive configuration. Defaults to 'flatcar-<channel>'.
  -l, --location             Azure image storage location. To list available locations run with '--locations'. Defaults to '${LOCATION}'.
  -S, --storage-account-type Type of storage account. Defaults to '${STORAGE_ACCOUNT_TYPE}'.
  -G, --hyper-v-generation   Hyper-V Generation to set against the image. Defaults to '${HYPER_V_GEN}'.
  --subscription             Azure subscription name or id.
  --skip-resource-group      Skip creation of resource group.
HELP_USAGE
}

az_login() {
	# Only log in if actually necessary.
	az account show --query user --output none 2>/dev/null || az login
}

while [[ $# -gt 0 ]]; do
key="$1"

case $key in
	-h|--help)
		usage
		exit 0
	;;
	-L|--locations)
		az_login
		az account list-locations
		exit 0
	;;
	-c|--channel)
		FLATCAR_LINUX_CHANNEL="$2"
		shift 2
	;;
	-v|--version)
		FLATCAR_LINUX_VERSION="$2"
		shift 2
	;;
	-i|--image-name)
		IMAGE_NAME="$2"
		shift 2
	;;
	-l|--location)
		LOCATION="$2"
		shift 2
	;;
	-g|--resource-group)
		RESOURCE_GROUP="$2"
		shift 2
	;;
	-S|--storage-account-type)
		STORAGE_ACCOUNT_TYPE="$2"
		shift 2
	;;
	-G|--hyper-v-generation)
		HYPER_V_GEN="$2"
		shift 2
	;;
	--subscription)
		SUBSCRIPTION="$2"
		shift 2
	;;
	--skip-resource-group)
		SKIP_RESOURCE_GROUP="TRUE"
		shift
	;;
	-u|--url)
		FLATCAR_URL="$2"
		shift 2
	;;
	*)
		echo "Unknown argument $1"
		echo
		usage
		exit 1
	;;
esac
done

IMAGE_NAME="${IMAGE_NAME:-flatcar-${FLATCAR_LINUX_CHANNEL}}"
: "${FLATCAR_URL:=https://${FLATCAR_LINUX_CHANNEL}.release.flatcar-linux.net/amd64-usr/${FLATCAR_LINUX_VERSION}/flatcar_production_azure_image.vhd.bz2}"

if [[ -z ${RESOURCE_GROUP-} ]]; then
	echo "--resource-group must be specified."
	echo
	usage
	exit 1
fi

az_login

[[ -z ${SKIP_RESOURCE_GROUP-} ]] &&
	az group create \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--name "${RESOURCE_GROUP}" \
		--location "${LOCATION}"

TEMP_DATA=$(mktemp -t az.XXXXXXXXXX)

az_disk_delete() {
	az disk delete \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--name "${IMAGE_NAME}" \
		--resource-group "${RESOURCE_GROUP}" \
		--yes
}

trap '
	rm -f -- "${TEMP_DATA}" || true
	# The disk is not needed afterwards.
	az_disk_delete || true
' EXIT

# shellcheck disable=SC2216
curl -f -L "${FLATCAR_URL}" | bzip2 -d | cp --sparse=always /dev/stdin "${TEMP_DATA}"

# Delete the disk in case it already exists, otherwise create will error.
az_disk_delete

DISK_ID=$(
	az disk create \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--name "${IMAGE_NAME}" \
		--resource-group "${RESOURCE_GROUP}" \
		--hyper-v-generation "${HYPER_V_GEN}" \
		--sku "${STORAGE_ACCOUNT_TYPE}" \
		--location "${LOCATION}" \
		--upload-size-bytes "$(stat -c %s "${TEMP_DATA}")" \
		--upload-type Upload |
			jq -r '.id'
)

SAS_URL=$(
	az disk grant-access \
		--ids "${DISK_ID}" \
		--access-level Write \
		--duration-in-seconds 120 |
			jq -r '.accessSAS'
)

azcopy copy \
	"${TEMP_DATA}" "${SAS_URL}" \
	--blob-type PageBlob

# We still need to do this even though we delete the disk on exit because
# otherwise it will be in the wrong state for image creation.
az disk revoke-access \
	--ids "${DISK_ID}"

# Delete the image in case it already exists, otherwise create will error or
# just do nothing, leaving the old content.
az image delete \
	${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
	--name "${IMAGE_NAME}" \
	--resource-group "${RESOURCE_GROUP}" \

az image create \
	${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
	--name "${IMAGE_NAME}" \
	--resource-group "${RESOURCE_GROUP}" \
	--hyper-v-generation "${HYPER_V_GEN}" \
	--source "${DISK_ID}" \
	--os-type linux
