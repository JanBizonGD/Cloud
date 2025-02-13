#!/bin/bash -x

if [[ "$#" -lt 1 ]] ; then
    echo =========== Error =============
    echo "Data should be inserted as follows :"
    echo "./<script>.sh -f <file-name>"
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
        echo PUBIP=.....
        echo REPURI=....
        echo REPURL=....
        exit 1
fi

PUBIP=$(grep -e PUBIP  $CRED | cut -f2 -d "=")
REPURI=$(grep -e REPURI  $CRED | cut -f2 -d "=")
REPURL=$(grep -e REPURL  $CRED | cut -f2 -d "=")
AWS_ACCESS_KEY_ID=$(grep -e AWS_ACCESS_KEY_ID  $CRED | cut -f2 -d "=")
AWS_SECRET_ACCESS_KEY=$(grep -e AWS_SECRET_ACCESS_KEY $CRED | cut -f2 -d "=")

if [ -z "$PUBIP" ] || [ -z "$REPURI" ] || [ -z "$REPURL" ] || [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "One of variables is empty."
        echo PUBIP: $PUBIP
        echo REPURI: $REPURI
        echo REPURL: $REPURL
        echo AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID
        echo AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
        exit 1
fi

EXPORT="export REPURI=$REPURI; export REPURL=$REPURL; export ACCESS_KEY=$AWS_ACCESS_KEY_ID; export ACCESS_SECRET=$AWS_SECRET_ACCESS_KEY"

ssh -t -o StrictHostKeyChecking=no  -i my_key.pem ec2-user@$PUBIP "$EXPORT; bash -s -l" <<'ENDSSH'
echo REPURI: $REPURI
echo "export REPURL=$REPURL" > /tmp/env.tmp
echo "export REPURI=$REPURI" >> /tmp/env.tmp
echo "export ACCESS_KEY=$ACCESS_KEY" >> /tmp/env.tmp
echo "export ACCESS_SECRET=$ACCESS_SECRET" >> /tmp/env.tmp

echo "================ Downloading dependencies ================"
sudo yum update -y && sudo yum install docker -y
sudo service docker start
sudo newgrp docker
source /tmp/env.tmp
rm /tmp/env.tmp
sudo usermod -aG docker ec2-user
#sudo su -s ec2-user - no password
sudo chown "$USER":"$USER" /home/"$USER"/.docker -R
sudo chmod g+rwx "$HOME/.docker" -R
docker --version

echo "================== Creating configuration ==============="
if [ ! -d ~/.aws/ ] ; then
        mkdir ~/.aws/
fi
echo "[default]
region=us-east-1
output=json" > ~/.aws/config
echo "[default]
aws_access_key_id=$ACCESS_KEY
aws_secret_access_key=$ACCESS_SECRET" > ~/.aws/credentials
unset ACCESS_KEY
unset ACCESS_SECRET

echo "================== Downloading image ==================="
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $REPURL
docker pull $REPURI

echo "================== Starting image ==================="
docker stop petclinic && docker rm petclinic
docker run  --platform linux/amd64 --rm -p 80:8080 --name petclinic $REPURI


ENDSSH
