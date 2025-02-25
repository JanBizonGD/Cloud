#!/bin/bash

# Do not delete:
# [----- EXPORT ENV ----]

sudo apt update && sudo apt install -y docker.io
sudo su -
sudo docker login $ACR_NAME.azurecr.io -u $AZ_ACCESS_KEY_ID -p $AZ_SECRET_ACCESS_KEY
sudo docker pull "$ACR_NAME.azurecr.io/petclinic:latest"
sudo docker run --rm  --platform linux/amd64 -p 80:8080 --name petclinic "$ACR_NAME.azurecr.io/petclinic:latest"
