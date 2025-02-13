#!/bin/bash -e

INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:User,Values=jbizon" | jq -r .Reservations[].Instances[] | jq -s '.')
INSTLEN=$(echo $INSTANCES | jq '. | length')
for ((i=0;i<$INSTLEN;i++)); do
        if [ $(echo $INSTANCES | jq -r .[$i].State.Name) = "running" ] ; then
                INSTID=$(echo $INSTANCES | jq -r .[$i].InstanceId)
        fi
done
if [ -z $INSTID ] ; then
        echo "============ Error =========== "
        echo "INSTID is empty"
        exit 1
fi
echo INSTID: $INSTID

INSTINFO=$(aws ec2 describe-instances \
    --instance-ids $INSTID \
    --query "Reservations[*].Instances[*].{
        InstanceID:InstanceId,
        PublicIP:PublicIpAddress,
        PrivateIP:PrivateIpAddress,
        SecurityGroups:SecurityGroups[*].GroupId,
        SubnetID:SubnetId,
        VPCID:VpcId,
        KeyName:KeyName,
        State:State.Name}" | jq .[0][0])
echo INSTINFO: $INSTINFO
SUBNET=$(echo $INSTINFO | jq -r .SubnetID)
echo SUBNET: $SUBNET
ASSOCIPID=$(aws ec2 describe-addresses --query "Addresses[]" | jq -r .[0].AssociationId)
echo ASSOCIPID: $ASSOCIPID
VPCID=$(echo $INSTINFO | jq -r .VPCID)
echo VPCID: $VPCID

ROUTEINFO=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPCID")
echo ROUTEINFO: $ROUTEINFO
GATEID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPCID" --query "InternetGateways[*].{ID:InternetGatewayId}" | jq -r .[0].ID)
echo GATEID: $GATEID
GROUPID=$(echo $INSTINFO | jq -r .SecurityGroups[])
echo GROUPID: $GROUPID
IP=$(echo $INSTINFO | jq -r .PublicIP)
echo IP: $IP
ALLOCID=$(aws ec2 describe-addresses --query "Addresses[?PublicIp=='$IP'].AllocationId" --output text)
echo ALLOCID: $ALLOCID




echo "-------"
aws ec2 disassociate-address --association-id $ASSOCIPID
echo "-------"
ROUTEASSOC=$(echo $ROUTEINFO | jq -r .RouteTables[].Associations[] | jq -s '.')
ROUTEASSOCLENG=$(echo $ROUTEASSOC | jq '. | length')
for ((i=0; i<$ROUTEASSOCLENG; i++ )); do
        echo assoc: $(echo $ROUTEASSOC | jq -r .[$i].RouteTableAssociationId)
        if [ $(echo $ROUTEASSOC | jq -r .[$i].Main ) = "false" ] ; then
                assoc=$(echo $ROUTEASSOC | jq -r .[$i].RouteTableAssociationId)
                route=$(echo $ROUTEASSOC | jq -r .[$i].RouteTableId)
                aws ec2 disassociate-route-table --association-id $assoc
                aws ec2 delete-route --route-table-id $route --destination-cidr-block 0.0.0.0/0
                aws ec2 delete-route-table --route-table-id $route
        fi
done
echo "-------"
echo "Terminating instance"
aws ec2 terminate-instances --instance-ids $INSTID
aws ec2 wait instance-terminated --instance-ids $INSTID
echo "-------"
aws ec2 release-address --allocation-id $ALLOCID
echo "-------"
aws ec2 revoke-security-group-ingress --group-id $GROUPID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 revoke-security-group-ingress --group-id $GROUPID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 revoke-security-group-egress --group-id $GROUPID --protocol -1 --cidr 0.0.0.0/0
echo "-------"
aws ec2 delete-security-group --group-id $GROUPID
echo "-------"
aws ec2 detach-internet-gateway --internet-gateway-id $GATEID --vpc-id $VPCID
echo "-------"
aws ec2 delete-internet-gateway --internet-gateway-id $GATEID
echo "-------"
aws ec2 delete-subnet --subnet-id $SUBNET
echo "-------"
aws ec2 delete-vpc --vpc-id $VPCID
echo "-------"

