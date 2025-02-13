#!/bin/bash -e

if [[ "$#" -lt 1 ]] ; then
    echo =========== Error =============
    echo "Data should be inserted as follows :"
    echo "./create_aws.sh -f <file-name>"
    exit 1
fi
while [ "$#" -gt 0 ] ; do
    case $1 in
        -f)
            shift 1
            CRED=$1
            ;;
        *)
            shift 1
            ;;
    esac
done
if [ -z $CRED ] || [ ! -f $CRED ] ; then
        echo =========== Error =============
        echo "Insert correct path to file with credentials to aws - key and secret."
        echo "\n"
        echo Inside file :
        echo AWS_ACCESS_KEY_ID=......
        echo AWS_SECRET_ACCESS_KEY=.....
        exit 1
fi

AWS_ACCESS_KEY_ID=$(grep -e AWS_ACCESS_KEY_ID  $CRED | cut -f2 -d "=")
AWS_SECRET_ACCESS_KEY=$(grep -e AWS_SECRET_ACCESS_KEY $CRED | cut -f2 -d "=")


echo "=================== Download dependencies ================="
apt update && apt install sudo curl unzip jq -y
sudo apt install apt-transport-https ca-certificates software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb https://download.docker.com/linux/ubuntu focal stable"
apt update && sudo apt install docker-ce -y
if [ ! -f awscliv2.zip ] ; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install --update
fi

echo "=================== Writing credentials ================="
if [ -z $AWS_ACCESS_KEY_ID ] || [ -z $AWS_ACCESS_KEY_ID ] ; then
        echo "Credentials inside $CRED are empty."
        echo "============ Override of credentials have been skipped =========="
else
        if [ ! -d ~/.aws ] ; then
                mkdir ~/.aws/
        fi
        echo "[default]
        region=us-east-1
        output=json" > ~/.aws/config
        echo "[default]
       aws_access_key_id=$AWS_ACCESS_KEY_ID
        aws_secret_access_key=$AWS_SECRET_ACCESS_KEY" > ~/.aws/credentials
fi
echo "=================== Creating and configuring VPC ================="
VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 | jq -r .Vpc.VpcId)
if [ -z $VPCID ]; then echo "Error VPCID"; exit 1; fi
SUBID=$(aws ec2 create-subnet --vpc-id $VPCID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a | jq -r .Subnet.SubnetId)
if [ -z $SUBID ]; then echo "Error SUBID"; exit 1; fi
GATEID=$(aws ec2 create-internet-gateway | jq -r .InternetGateway.InternetGatewayId)
if [ -z $GATEID ]; then echo "Error GATEID"; exit 1; fi
aws ec2 attach-internet-gateway --vpc-id $VPCID --internet-gateway-id $GATEID
ROUTEID=$(aws ec2 create-route-table --vpc-id $VPCID | jq -r .RouteTable.RouteTableId )
if [ -z $ROUTEID ]; then echo "Error ROUTEID"; exit 1; fi
aws ec2 create-route --route-table-id $ROUTEID --destination-cidr-block 0.0.0.0/0 --gateway-id $GATEID > /dev/null
ASSID=$(aws ec2 associate-route-table --subnet-id $SUBID --route-table-id $ROUTEID | jq -r .AssociationId)
if [ -z $ASSID ]; then echo "Error ASSID"; exit 1; fi
echo "=================== Creating and configuring security groups ================="
GRID=$(aws ec2 create-security-group --group-name MySecurityGroup --description "Allow SSH and HTTP" --vpc-id $VPCID | jq -r .GroupId) > /dev/null
if [ -z $GRID ]; then echo "Error GRID"; exit 1; fi
aws ec2 authorize-security-group-ingress --group-id $GRID --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $GRID --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
ALLOCIP=$(aws ec2 allocate-address)
if [ -z "$ALLOCIP" ]; then echo "Error ALLOCIP"; exit 1; fi
ALLOCID=$(echo $ALLOCIP | jq -r .AllocationId)
if [ -z $ALLOCID ]; then echo "Error ALLOCID"; exit 1; fi
PUBIP=$(echo $ALLOCIP | jq -r .PublicIp )
if [ -z $PUBIP ]; then echo "Error PUBIP"; exit 1; fi
REGION=$(echo $ALLOCIP | jq -r .NetworkBorderGroup)
if [ -z $REGION ]; then echo "Error REGION"; exit 1; fi

echo "=================== Creating ECR repostiory ================="
REP=$(aws ecr describe-repositories | jq -r .)
if [ -z "$REP" ]; then echo "Error REP"; exit 1; fi
REPName=$(echo $REP | jq -r .repositories[0].repositoryName)
if [ $REPName != "jbizon/petclinic" ] ; then
        REP=$(aws ecr create-repository --repository-name jbizon/petclinic)
        if [ -z "$REP" ]; then echo "Error REP"; exit 1; fi
                REPURI=$(echo $REP | jq -r .repository.repositoryUri)
else
        REP=$(aws ecr describe-repositories | jq -r .)
        REPURI=$(echo $REP | jq -r .repositories[0].repositoryUri)
fi
if [ -z $REPURI ]; then echo "Error REPURI"; exit 1; fi
REPURL=$(echo "$REPURI" | grep -oP "^[a-zA-Z0-9.-]*")
if [ -z $REPURL ]; then echo "Error REPURL"; exit 1; fi

sed -i '3,$d' $CRED
echo "
REPURI=$REPURI
REPURL=$REPURL
PUBIP=$PUBIP
" >> $CRED

echo "=================== Creating EC2 instance ================="
KEY_EXIST=$(aws ec2 describe-key-pairs --query "KeyPairs[*].KeyName" | jq '.[] |  contains("my_key")')
echo 'does_key_exist?:' $KEY_EXIST
if ! $KEY_EXIST || [ -z $KEY_EXIST ]; then
    aws ec2 create-key-pair --key-name my_key --query "KeyMaterial" --output text > my_key.pem
fi
INST=$(aws ec2 run-instances --image-id ami-085ad6ae776d8f09c --count 1 --instance-type t2.micro --key-name my_key --security-group-ids $GRID --subnet-id $SUBID --associate-public-ip-address --tag-specifications 'ResourceType=instance,Tags=[{Key=User,Value=jbizon}]')
INSTID=$(echo $INST | jq -r .Instances[0].InstanceId)
if [ -z $INSTID ]; then echo "Error INSTID"; exit 1; fi
echo "======== Wainting until instance is running ========="
aws ec2 wait instance-running --instance-ids $INSTID
aws ec2 associate-address --instance-id $INSTID --allocation-id $ALLOCID > /dev/null
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPURL

#docker tag petclinic:latest $REPURI:latest
docker tag 593546282661.dkr.ecr.us-east-1.amazonaws.com/jbizon/petclinic:latest $REPURI:latest
docker push $REPURI:latest

chmod 400 my_key.pem
echo IP: $PUBIP

