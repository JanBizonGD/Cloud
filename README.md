# Cloud
Repository contains automatic setup of 3 major cloud providers : AWS, GoogleCloud, Azure and deployment of spring petclinic project. 
Scripts were executed on ubuntu container - **not to override aws credentials** related to GridDynamics. I also used cloudguru AWS sandbox.

### Build
Before launching petclinic website build docker image and name it : `petclinic:latest`. **(Important: When I was doing this, I used containerd and build with (multiplatform): `docker buildx build --platform linux/amd64,linux/arm64 -t...`). To turn on mutliplatform (containerd) in Docker Desktop - Settings/General/Use containerd for pulling and storing images - to check on** 

### Expected results:
![](./doc/images/aws/result.png)


### Test
To view website, enter yours instance public IP address to web browser.
![](./doc/images/aws/web.png )

---------------------------------

## AWS
### Setup
Requirements:
- LinuxOS - preferably Ubuntu 20.04
- access to AWS
- key access token
- network connection between local machine and aws / ubuntu repositories


Then create file containing key access token.


Credential file format:
```
AWS_ACCESS_KEY_ID=....
AWS_SECRET_ACCESS_KEY=.........
```

##### To obtain key - go to IAM inside AWS Dashboard.
![](./doc/images/aws/key1.png)
![](./doc/images/aws/key2.png)
![](./doc/images/aws/key3.png)

### Usage of automatic setup
##### <create_aws.sh> overrides aws credentials created with `aws configure` !
##### Region is hardcoded - at the moment without possibility to specify on commandline!
```
<create_aws.sh> -f <cred.txt>
```
Values are automaticly assiged after creating instance to file with credentials:
```
PUBIP=.....
REPURI=....
REPURL=....
```
At the end of create aws - IP of instance is presented. AWS linux was used as a base image for instance.
```
<lauch_aws.sh> -f <cred.txt>
```
```
<delete_aws.sh>
```


##### Instance that will be deleted depends on tags specified inside script. If there are more then one instance running with same tags, behaviour is undefined (unknown instance will be deleted).
* TODO: specify tags from command line
* TODO: proper turn off after CTRL+C
* TODO: naming ssh key, and specifing location
* TODO: Specify region
* TODO: Do not override created credentials
* TODO: specify other hardcoded values like: repository name, key name, etc.
---------------------------------

## GoogleCloud
### Setup
Requirements:
- LinuxOS - preferably Ubuntu 20.04
- access to Google Cloud
- service access credentials
- network connection between local machine and google cloud

Before you can access GCP and use `gcloud` you need to have credentials in form of file. Structure of the file is described below.

Credential file format:
```
{
  "type": "service_account",
  "project_id": "playground-s-11-3.....",
  "private_key_id": "7f2ff422................",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQI ........ ,
  "client_email": "<account_id>@<project_id>.iam.gserviceaccount.com",
  "client_id": "1117634874.........",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/cli-service-account-1%40<project_id>.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
```
How to get credentaials:
![](./doc/images/gcp/service-account.png)
![](./doc/images/gcp/role.png)
![](./doc/images/gcp/key.png)

**It is important to give right roles to service account.** 


### Usage of automatic setup
```
<config.sh> -f <cred.json> -p <project-name> -r <region>
```
`cred.json` is described in above example. `project name` is equivalent with `project-id` : `playground-s-11-3.....`. `region` - example: us-central1, avalable regions are simular to: https://cloud.google.com/artifact-registry/docs/repositories/repo-locations (note that this example refers to artifact registry).

**(Note)** that project name can be obtained from credential file. Region is arbitral decition. Zone is hardcoded to always use `a`.

```
<run.sh> <project-name>
```
`run.sh` is script that is automaticly coppied into remote instance for purpose of setup and launch petclinic project.

**Instance are automaticly deleted after full setup and registration of clean up funciton. After that when user press combination of CTRL+C everything that was created will be deleted.**

TODO: If there is resource with same name as that specified inside script then it will be used and deleted when pressed CTRL+C. It is not intended behaviour.
TODO: Specify from command line zone 
TODO: Specify form command line additional tags
TODO: GCR possibly not private - to be checked

---------------------------------

## Azure
tbc.
---------------------------------
