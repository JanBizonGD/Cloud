#!/bin/bash -e

function clean_up()
{
    echo "================= Deletion ======================"
    gcloud compute firewall-rules describe allow-ssh &> /dev/null
    if [[ $? -eq 0 ]]; then
        echo "================= Delete firewall rule ======================"
        gcloud compute firewall-rules delete allow-ssh --quiet
    fi

    gcloud compute firewall-rules describe allow-http &> /dev/null
    if [[ $? -eq 0 ]]; then
        echo "================= Delete firewall rule ======================"
        gcloud compute firewall-rules delete allow-http --quiet
    fi

    gcloud compute instances describe $INST_NAME --zone=$ZONE --format="value(name)" &> /dev/null
    if [[ $? -eq 0 ]]; then
        echo "================= Delete instance ======================"
        gcloud compute instances delete $INST_NAME --zone=$ZONE --quiet
    fi
    
    if gcloud compute addresses list --filter="name=$IP_NAME" --format="value(address)" | grep -q "$IP_NAME"; then
        echo "================= Delete ip ======================"
        gcloud compute addresses delete $IP_NAME --region=$REG --quiet
    fi

    
    if gcloud compute networks subnets list --filter="network:$VPC_NAME" --format="value(name)" | grep -q "$SUB_NAME"; then
        echo "================= Delete subnet ======================"
        gcloud compute networks subnets delete $SUB_NAME --region=$REG --quiet
    fi

    gcloud compute networks describe $VPC_NAME --format="value(name)" &> /dev/null
    if [[ $? -eq 0 ]]; then
        echo "================= Delete VPC ======================"
        gcloud compute networks delete $VPC_NAME --quiet
    fi

    gcloud container images list-tags gcr.io/$PROJ/petclinic --limit=1 &>/dev/null
    if [[ $? -eq 0 ]]; then
        echo "================= Delete repository ======================"
        gcloud container images delete --force-delete-tags gcr.io/$PROJ/petclinic:latest --quiet 
        gcloud artifacts repositories delete gcr.io --location=us --quiet 
    fi

    echo "================= Turn off services ======================"
    gcloud services disable containerregistry.googleapis.com
    gcloud services disable artifactregistry.googleapis.com
    echo "================= End of deletion ======================"

    exit 0
}

if [[ "$#" -lt 3 ]] ; then
    echo =========== Error =============
    echo "Data should be inserted as follows :"
    echo "./<config.sh> -f <cred-file> -p <proj-name> -r <region>"
    exit 1
fi
while [ "$#" -gt 0 ] ; do
    case $1 in
        -f)
            shift 1
            CRED=$1
            ;;
        -p)
            shift 1
            PROJ=$1
            ;;
        -r)
            shift 1
            REG=$1
            ;;
        *)
            shift 1
            ;;
    esac
done

if [ -z $CRED ] || [ ! -f $CRED ] ; then
        echo =========== Error =============
        echo "Insert correct path to file with credentials to google cloud."
        exit 1
fi

if [ -z $PROJ ] ; then
        echo =========== Error =============
        echo "Insert project name, ex: -p playground-s-11-154d53eb"
        exit 1
fi

if [ -z $REG ] ; then
        echo =========== Error =============
        echo "Insert region name, ex: -r us-central1"
        exit 1
fi

echo "================= Install packages ======================"
if [[ $(apt list -i sudo apt-transport-https ca-certificates gnupg curl software-properties-common | wc -l )  -lt 7 ]] ; then
    apt update && apt-get install -y sudo apt-transport-https ca-certificates gnupg curl software-properties-common
fi

if [[ $(apt list -i google-cloud-cli | wc -l )  -lt 2 ]] ; then
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    sudo apt-get update && sudo apt-get install -y google-cloud-cli
fi


if [[ $(apt list -i docker-ce | wc -l )  -lt 2 ]]  ; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb https://download.docker.com/linux/ubuntu focal stable" -y
    apt update && sudo apt install docker-ce -y
fi

ZONE=$REG-a
VPC_NAME=petclinic-net
SUB_NAME=http-subnet
IP_NAME=petclinic-ip
INST_NAME=petclinic-server

echo "================= Auth to GCP ======================"
#gcloud init --console-only --quiet
gcloud auth activate-service-account --key-file=$CRED --quiet
gcloud config set project $PROJ --quiet  &> /dev/null
gcloud auth login --cred-file=$CRED --quiet


if ! gcloud compute networks describe $VPC_NAME --format="value(name)"  &>/dev/null ; then
    echo "================= Create VPC ======================"
    gcloud compute networks create $VPC_NAME --subnet-mode=custom
fi


if ! gcloud compute networks subnets list --filter="network:$VPC_NAME" --format="value(name)" | grep -q "$SUB_NAME"; then
    echo "================= Create subnet ======================"
    gcloud compute networks subnets create $SUB_NAME \
    --network=$VPC_NAME \
    --region=$REG \
    --range=10.0.0.0/24
fi


if ! gcloud compute addresses describe "$IP_NAME" --region=$REG --format="value(address)"  &>/dev/null; then
    echo "================= Create IP ======================"
    gcloud compute addresses create $IP_NAME --region=$REG
fi
IPADD=$(gcloud compute addresses describe $IP_NAME --region=$REG --format="get(address)")

echo "================= Turn on services ======================"
gcloud services enable containerregistry.googleapis.com
gcloud services enable artifactregistry.googleapis.com


if ! gcloud compute instances describe $INST_NAME --zone=$ZONE --format="value(name)" &>/dev/null ; then
    echo "================= Create instance ======================"
    gcloud compute instances create  $INST_NAME --network=$VPC_NAME --subnet=$SUB_NAME --zone=$ZONE --machine-type=e2-micro --preemptible --tags=jbizon,allow-ssh,allow-http --address=$IPADD
fi


if ! gcloud compute firewall-rules describe allow-ssh &>/dev/null; then
    echo "================= Create firewall rule ======================"
    gcloud compute firewall-rules create allow-ssh --direction=INGRESS --priority=1000 --network=$VPC_NAME --action=ALLOW --rules=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=allow-ssh
fi
if ! gcloud compute firewall-rules describe allow-http &>/dev/null; then
    echo "================= Create firewall rule ======================"
    gcloud compute firewall-rules create allow-http --direction=INGRESS --priority=1000 --network=$VPC_NAME --action=ALLOW --rules=tcp:80 --source-ranges=0.0.0.0/0 --target-tags=allow-http
fi
echo "================= Register trap ======================"
trap clean_up SIGINT


echo "================= Auth to docker, tag and push ======================"
gcloud auth configure-docker gcr.io --quiet
docker tag petclinic gcr.io/$PROJ/petclinic:latest
docker push gcr.io/$PROJ/petclinic:latest

echo "================= Connect to instance ======================"
echo IP: $IPADD
gcloud compute scp ./run.sh user@$INST_NAME:. --zone=$ZONE
set +e
gcloud compute ssh user@$INST_NAME --zone=$ZONE -- "chmod u+x ./run.sh && bash ./run.sh $PROJ"
set -e
echo "Press CTRL+C to clean and close ..."
while true ; do sleep 1; done

