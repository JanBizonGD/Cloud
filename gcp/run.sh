#!/bin/bash

PROJ=$1
sudo apt update && sudo apt install -y docker.io
sudo gcloud auth configure-docker gcr.io
sudo docker pull gcr.io/$PROJ/petclinic:latest
sudo docker run --rm  --platform linux/amd64 -p 80:8080 --name petclinic gcr.io/$PROJ/petclinic:latest
