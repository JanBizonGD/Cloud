#!/bin/bash -e

function clean_up() {
    echo "================= Deleting resources ======================"
    echo "================= Query disks of VM ======================"
    DATA_DISKS=$(az vm show -d --name $VM_NAME --query "storageProfile.dataDisks[].managedDisk.id" -o tsv)
    OS_DISKS=$(az vm show -d --name $VM_NAME --query "storageProfile.osDisk.managedDisk.id" -o tsv)
    echo "================= Deleting VM ======================"
    az resource delete --name $VM_NAME --resource-type Microsoft.Compute/virtualMachines
    echo "================= Deleting disks ======================"
    for dd in $DATA_DISKS; do
        az disk delete --ids $dd --yes
    done
    for od in $OS_DISKS; do
        az disk delete --ids $od --yes
    done
    echo "================= Deleting VM NIC ======================"
    NIC_NAME=${VM_NAME}VMNic
    az resource delete --name $NIC_NAME --resource-type Microsoft.Network/networkInterfaces
    echo "================= Deleting Network Security Group ======================"
    az resource delete --name $NS_GROUP_NAME --resource-type Microsoft.Network/networkSecurityGroups
    echo "================= Deleting PublicIP ======================"
    az resource delete --name $IP_NAME --resource-type Microsoft.Network/publicIPAddresses
    echo "================= Deleting ACR ======================"
    az resource delete --name $ACR_NAME --resource-type Microsoft.ContainerRegistry/registries
    echo "================= Deleting Vnet ======================"
    az resource delete --name $VNET_NAME --resource-type Microsoft.Network/virtualNetworks

    echo "================= End of deletion ======================"
}


if [[ "$#" -lt 2 ]] ; then
    echo =========== Error =============
    echo "Data should be inserted as follows :"
    echo "./<config.sh> -f <cred-file> -g <res-group>"
    exit 1
fi
while [ "$#" -gt 0 ] ; do
    case $1 in
        -f)
            shift 1
            CRED=$1
            ;;
        -g)
            shift 1
            RES_GROUP=$1
            ;;
        *)
            shift 1
            ;;
    esac
done

if [ -z $CRED ] || [ ! -f $CRED ] ; then
        echo =========== Error =============
        echo "Insert correct path to file with credentials to azure cloud."
        exit 1
fi

if [ -z $RES_GROUP ] ; then
        echo =========== Error =============
        echo "Insert resource group name, ex: -g 1-1d0d00e6-playground-sandbox "
        exit 1
fi

AZ_ACCESS_KEY_ID=$(grep -e AZ_ACCESS_KEY_ID  $CRED | cut -f2 -d "=")
AZ_SECRET_ACCESS_KEY=$(grep -e AZ_SECRET_ACCESS_KEY $CRED | cut -f2 -d "=")
AZ_TENANT_ID=$(grep -e TENANT_ID  $CRED | cut -f2 -d "=")
if [ -z $AZ_ACCESS_KEY_ID ] || [ -z $AZ_SECRET_ACCESS_KEY ] || [ -z $AZ_TENANT_ID ] ; then
    echo "Wrong format of credential file !"
    echo "Insert credentails as follows:"
    echo "AZ_ACCESS_KEY_ID=....\n\
    AZ_SECRET_ACCESS_KEY=...\n\
    AZ_TENANT_ID=........\n"
fi

echo "================= Install packages ======================"
if [[ $(apt list -i sudo curl apt-transport-https ca-certificates software-properties-common docker-ce | wc -l )  -lt 7 ]] ; then
    apt update && apt install -y sudo curl apt-transport-https ca-certificates software-properties-common
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb https://download.docker.com/linux/ubuntu focal stable" -y
    apt update && sudo apt install docker-ce -y
fi


VNET_NAME="MyVnet"
SUBNET_NAME="MySubnet"
ACR_NAME="myacr1234jb"
IP_NAME="MyPublicIP"
VM_NAME="MyVM"
NS_GROUP_NAME="MyNSG"

echo "================= Login and configuration ======================"
# TODO : login with sub id instead of tenant id
#az account set --subscription $AZ_SUB_ID
#AZ_TENANT_ID=$(az account show --query tenantId --output tsv)

az login --service-principal --username $AZ_ACCESS_KEY_ID --password $AZ_SECRET_ACCESS_KEY --tenant $AZ_TENANT_ID
az config set defaults.group=$RES_GROUP

echo "================= Create VNet ======================"
az network vnet create --resource-group $RES_GROUP --name $VNET_NAME --address-prefix 10.0.0.0/16 --query "newVNet.provisioningState" -o tsv
echo "================= Create Subnet ======================"
az network vnet subnet create --resource-group $RES_GROUP --vnet-name $VNET_NAME --name $SUBNET_NAME --address-prefix 10.0.0.0/24 --query "provisioningState" -o tsv
echo "================= Create ACR ======================"
az acr create --resource-group $RES_GROUP --name $ACR_NAME --sku Basic --query "provisioningState" -o tsv
echo "================= Create IP ======================"
az network public-ip create --resource-group $RES_GROUP --name $IP_NAME --allocation-method Static --query "publicIp.provisioningState" -o tsv

echo "================= Create Network security group ======================"
az network nsg create --resource-group $RES_GROUP --name $NS_GROUP_NAME &>/dev/null
az network nsg rule create --resource-group $RES_GROUP --nsg-name $NS_GROUP_NAME --name Allow-HTTP --protocol tcp --priority 1000 --destination-port-ranges 80 --access Allow --direction Inbound --query "provisioningState" -o tsv
az network nsg rule create --resource-group $RES_GROUP --nsg-name $NS_GROUP_NAME --name Allow-SSH --protocol tcp --priority 1001 --destination-port-ranges 22 --access Allow --direction Inbound --query "provisioningState" -o tsv

echo "================= Register Trap ======================"
trap clean_up SIGINT

echo "================= Login to ACR ======================"
az acr login --name $ACR_NAME
echo "================= Login to Docker ======================"
docker login $ACR_NAME.azurecr.io -u $AZ_ACCESS_KEY_ID -p $AZ_SECRET_ACCESS_KEY
echo "================= Docker tag and push ======================"
docker tag petclinic $ACR_NAME.azurecr.io/petclinic:latest
docker push $ACR_NAME.azurecr.io/petclinic:latest

echo "================= Create Run.sh ======================"
EXP_TEXT="ACR_NAME=$ACR_NAME;AZ_ACCESS_KEY_ID=$AZ_ACCESS_KEY_ID;AZ_SECRET_ACCESS_KEY=$AZ_SECRET_ACCESS_KEY;"
sed -r -e 's|# \[----- EXPORT ENV ----\]|'"$EXP_TEXT"'|g' run.sh > tmp.sh

echo "================= Create VM ======================"
az vm create \
    --resource-group $RES_GROUP \
    --name $VM_NAME \
    --image Ubuntu2204 \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_NAME \
    --nsg $NS_GROUP_NAME \
    --public-ip-address $IP_NAME \
    --admin-username azureuser \
    --generate-ssh-keys \
    --custom-data tmp.sh

echo "================= Removing tmp ======================"
rm -f tmp.sh

echo "Press CTRL+C to clean and close ..."
while true ; do sleep 1; done
