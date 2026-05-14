#!/bin/bash

set -euo pipefail

# Default values
FLATCAR_LINUX_CHANNEL=stable
FLATCAR_LINUX_VERSION=current
LOCATION=westeurope
STORAGE_ACCOUNT_TYPE=Standard_LRS

usage() {
	cat <<HELP_USAGE
Usage: $0 [OPTION...]

 Required arguments:
  -g, --resource-group        Azure resource group.
  -s, --storage-account-name  Azure storage account name. Must be between 3 and 24 characters and unique within Azure.

 Optional arguments:
  -c, --channel              Flatcar Linux release channel. Defaults to '${FLATCAR_LINUX_CHANNEL}'.
  -v, --version              Flatcar Linux version. Defaults to '${FLATCAR_LINUX_VERSION}'.
  -i, --image-name           Image name, which will be used later in Lokomotive configuration. Defaults to 'flatcar-<channel>'.
  -l, --location             Azure image storage location. To list available locations run with '--locations'. Defaults to '${LOCATION}'.
  -S, --storage-account-type Type of storage account. Defaults to '${STORAGE_ACCOUNT_TYPE}'.
  --subscription             Azure subscription name or id.
  --skip-resource-group      Skip creation of resource group.
  --skip-storage-account     Skip creation of storage account.
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
	-s|--storage-account-name)
		export AZURE_STORAGE_ACCOUNT="$2"
		shift 2
	;;
	-S|--storage-account-type)
		STORAGE_ACCOUNT_TYPE="$2"
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
	--skip-storage-account)
		SKIP_STORAGE_ACCOUNT="TRUE"
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

if [[ -z ${AZURE_STORAGE_ACCOUNT-} ]]; then
	echo "--storage-account-name must be specified."
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

[[ -z ${SKIP_STORAGE_ACCOUNT-} ]] &&
	az storage account create \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--name "${AZURE_STORAGE_ACCOUNT}" \
		--resource-group "${RESOURCE_GROUP}" \
		--location "${LOCATION}" \
		--sku "${STORAGE_ACCOUNT_TYPE}" \
		--kind StorageV2

# Obtain storage key for created storage account
export AZURE_STORAGE_KEY
AZURE_STORAGE_KEY=$(
	az storage account keys list \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--resource-group "${RESOURCE_GROUP}" \
		--account-name "${AZURE_STORAGE_ACCOUNT}" |
			jq -r '.[0].value'
)

az storage container create \
	${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
	--name vhds

TEMP_DATA=$(mktemp -t az.XXXXXXXXXX)
trap 'rm -f -- "${TEMP_DATA}"' EXIT
# shellcheck disable=SC2216
curl -f -L "${FLATCAR_URL}" | bzip2 -d | cp --sparse=always /dev/stdin "${TEMP_DATA}"

az storage blob upload \
	${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
	--container-name vhds \
	--name "${IMAGE_NAME}.vhd" \
	--file "${TEMP_DATA}" \
	--type page

# Create disk from uploaded image and save it's ID
DISK_ID=$(
	az disk create \
		${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
		--name "${IMAGE_NAME}" \
		--resource-group "${RESOURCE_GROUP}" \
		--source "https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/vhds/${IMAGE_NAME}.vhd" |
			jq -r '.id'
)

az image create \
	${SUBSCRIPTION:+--subscription "${SUBSCRIPTION}"} \
	--name "${IMAGE_NAME}" \
	--resource-group "${RESOURCE_GROUP}" \
	--source "${DISK_ID}" \
	--os-type linux
