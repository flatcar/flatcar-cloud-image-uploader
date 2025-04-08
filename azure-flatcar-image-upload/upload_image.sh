#!/bin/bash
set -o errexit
set -o pipefail

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
  -l, --location             Azure location to storage image. To list available locations run with '--locations'. Defaults to '${LOCATION}'.
  -S, --storage-account-type Type of storage account. Defaults to '${STORAGE_ACCOUNT_TYPE}'.
  --subscription             Azure subscription name or id.
  --skip-resource-group      Skip creation of resource group.
  --skip-storage-account     Skip creation of storage account.
HELP_USAGE
}

while [[ $# -gt 0 ]]; do
key="$1"

case $key in
	-h|--help)
		usage
		exit 0
	;;
	-L|--locations)
		az login
		az account list-locations
		exit 0
	;;
	-c|--channel)
		FLATCAR_LINUX_CHANNEL="$2"
		shift
		shift
	;;
	-v|--version)
		FLATCAR_LINUX_VERSION="$2"
		shift
		shift
	;;
	-i|--image-name)
		IMAGE_NAME="$2"
		shift
		shift
	;;
	-l|--location)
		LOCATION="$2"
		shift
		shift
	;;
	-g|--resource-group)
		RESOURCE_GROUP="$2"
		shift
		shift
	;;
	-s|--storage-account-name)
		STORAGE_ACCOUNT_NAME="$2"
		shift
		shift
	;;
	-S|--storage-account-type)
		STORAGE_ACCOUNT_TYPE="$2"
		shift
		shift
	;;
	--subscription)
		SUBCRIPTION="$2"
		shift
		shift
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
		shift
		shift
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

if [[ -z "${RESOURCE_GROUP}" ]]; then
	echo "--resource-group must be specified."
	echo
	usage
	exit 1
fi

if [[ -z "${STORAGE_ACCOUNT_NAME}" ]]; then
	echo "--storage-account-name must be specified."
	echo
	usage
	exit 1
fi

# Login to azure
az login

if [[ -n "${SUBCRIPTION}" ]]; then
	echo "Using Azure subscription: ${SUBCRIPTION}"
	az account set -s $SUBCRIPTION
fi

[[ -z "${SKIP_RESOURCE_GROUP}" ]] && az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
[[ -z "${SKIP_STORAGE_ACCOUNT}" ]] && az storage account create \
	--resource-group $RESOURCE_GROUP \
	--location $LOCATION \
	--name $STORAGE_ACCOUNT_NAME \
	--kind StorageV2 \
	--sku $STORAGE_ACCOUNT_TYPE

# Obtain storage key for created storage account
KEY=$(az storage account keys list \
	--resource-group $RESOURCE_GROUP \
	--account-name $STORAGE_ACCOUNT_NAME | jq -r '.[0].value')

# Make sure there is no old images
rm -f flatcar_production_azure_image.vhd flatcar_production_azure_image.vhd.bz2

# Download Flatcar image
if [ ! -z "$FLATCAR_URL" ]; then
	curl -o flatcar_production_azure_image.vhd.bz2 "$FLATCAR_URL"
else
	curl -LO https://${FLATCAR_LINUX_CHANNEL}.release.flatcar-linux.net/amd64-usr/${FLATCAR_LINUX_VERSION}/flatcar_production_azure_image.vhd.bz2
fi

# And unpack it
bzip2 -d flatcar_production_azure_image.vhd.bz2

# Upload image to Azure
azure-vhd-utils upload \
	--localvhdpath flatcar_production_azure_image.vhd \
	--stgaccountname $STORAGE_ACCOUNT_NAME \
	--blobname $IMAGE_NAME \
	--stgaccountkey "$KEY"

# Cleanup after downloading
rm -f flatcar_production_azure_image.vhd flatcar_production_azure_image.vhd.bz2

# Create disk from uploaded image and save it's ID
DISK_ID=$(az disk create --name $IMAGE_NAME -g $RESOURCE_GROUP --source https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/vhds/$IMAGE_NAME.vhd | jq -r '.id')

# Create image
az image create \
	-g $RESOURCE_GROUP \
	--name $IMAGE_NAME \
	--source $DISK_ID \
	--os-type linux
