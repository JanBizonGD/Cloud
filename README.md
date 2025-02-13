# Cloud
Repository contains automatic setup of 3 major cloud providers : AWS, GoogleCloud, Azure and deployment of spring petclinic project. 
---------------------------------

## AWS
### Setup
Requirements:
- LinuxOS - preferably Ubuntu 20.04
- access to AWS
- key access token
- network connection between local machine and aws / ubuntu repositories

Before launching petclinic website build docker image and name it : `petclinic:latest`. **(Important: When I was doing this, I used containerd and build with (multiplatform): `docker buildx build --platform linux/amd64,linux/arm64 -t...`). To turn on mutliplatform (containerd) in Docker Desktop - Settings/General/Use containerd for pulling and storing images - to check on** 
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
At the end of create aws - IP of instance is presented.
```
<lauch_aws.sh> -f <cred.txt>
```
```
<delete_aws.sh>
```

Expected results:
![](./doc/images/aws/result.png)


### Test
To view website, enter yours instance public IP address to web browser.
![](./doc/images/aws/web.png )


##### Instance that will be deleted depends on tags specified inside script. If there are more then one instance running with same tags, behaviour is undefined (unknown instance will be deleted).
* TODO: specify tags from command line
* TODO: proper turn off after CTRL+C
* TODO: naming ssh key, and specifing location
* TODO: Specify region
* TODO: Do not override created credentials
* TODO: specify other hardcoded values like: repository name, key name, etc.
---------------------------------

## GoogleCloud
tbc.
---------------------------------

## Azure
tbc.
---------------------------------
