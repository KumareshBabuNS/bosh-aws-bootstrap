#!/bin/bash -e

echo "Add necessary repositories to APT"
sudo apt-add-repository ppa:brightbox/ruby-ng -y
sudo apt-get update --fix-missing


echo "Install bosh-init"
wget https://s3.amazonaws.com/bosh-init-artifacts/bosh-init-0.0.96-linux-amd64 -O bosh-init
sudo install -m0755 bosh-init /usr/local/bin/bosh-init
rm bosh-init

echo "Test that bosh-init was installed"
bosh-init -v

echo "Install compilation packages and Ruby"
sudo apt-get install -y build-essential zlibc zlib1g-dev ruby-dev openssl libxslt-dev libxslt1-dev libpq-dev libxml2-dev libssl-dev libreadline6 libreadline6-dev libyaml-dev libsqlite3-dev sqlite3 software-properties-common libmysqlclient-dev ruby2.1 unzip
sudo update-alternatives --set ruby /usr/bin/ruby2.1

echo "Test that Ruby was correctly installed"
ruby --version

echo "Install the BOSH CLI"
sudo gem install bosh_cli --no-ri --no-rdoc --no-user-install

echo "Download and install the AWS CLI"
curl -O https://s3.amazonaws.com/aws-cli/awscli-bundle.zip
unzip awscli-bundle.zip
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
rm awscli-bundle* -rf

echo "Configure the AWS credentials and Region"
aws configure

echo "Create a Virtual Private Cloud (VPC)"
vpc_id=$(aws ec2 create-vpc --cidr-block '10.0.0.0/16' --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $vpc_id --tags Key=Name,Value=training_vpc

echo "Create a Subnet:"
subnet_id=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.0.0/24 --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $subnet_id --tags Key=Name,Value=training_subnet
avz=$(aws ec2 describe-subnets --subnet-ids $subnet_id --query 'Subnets[].AvailabilityZone' --output text)

echo "Create an Internet Gateway and attach it to the VPC:"
gateway_id=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $gateway_id --tags Key=Name,Value=training_gateway
aws ec2 attach-internet-gateway --internet-gateway-id $gateway_id --vpc-id $vpc_id

echo "Create a Route Table and associate it with the Subnet:"
route_table_id=$(aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $route_table_id --tags Key=Name,Value=training_route_table
aws ec2 associate-route-table --route-table-id $route_table_id --subnet-id $subnet_id

echo "Create a Route:"
aws ec2 create-route --gateway-id $gateway_id --route-table-id $route_table_id --destination-cidr-block 0.0.0.0/0

echo "Create a Security Group:"
sg_id=$(aws ec2 create-security-group --vpc-id $vpc_id --group-name training_sg --description "Security Group bog BOSH deployment" --query 'GroupId' --output text)
aws ec2 create-tags --resources $sg_id --tags Key=Name,Value=training_sg

echo "Add Security Group rules:"

echo "Allow ICMP traffic:"
aws ec2 authorize-security-group-ingress --group-id $sg_id --ip-permissions '[{"IpProtocol": "icmp", "FromPort": -1, "ToPort": -1, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'

echo "Allow SSH access:"
aws ec2 authorize-security-group-ingress --group-id $sg_id --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'

echo "Allow bosh-init to access BOSH Agent:"
aws ec2 authorize-security-group-ingress --group-id $sg_id --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 6868, "ToPort": 6868, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'

echo "Allow the BOSH CLI to access BOSH Director:"
aws ec2 authorize-security-group-ingress --group-id $sg_id --ip-permissions '[{"IpProtocol": "tcp", "FromPort": 25555, "ToPort": 25555, "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'

echo "Allow all TCP and UDP traffic inside the security group:"
aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol '-1' --port -1 --source-group $sg_id

echo "Create an Elastic IP:"
eip_id=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
eip=$(aws ec2 describe-addresses --allocation-ids $eip_id --query 'Addresses[].PublicIp' --output text)

echo "Create a Key Pair:"
key_name=$(hostname)-training_key
mkdir deployment
aws ec2 create-key-pair --key-name $key_name --query 'KeyMaterial' --output text > deployment/bosh.pem
chmod 400 ~/deployment/bosh.pem

echo "Store all variables in a file for later use"
cat > ~/deployment/vars <<EOF
export vpc_id=$vpc_id
export subnet_id=$subnet_id
export gateway_id=$gateway_id
export route_table_id=$route_table_id
export sg_id=$sg_id
export eip_id=$eip_id
export eip=$eip
export avz=$avz
export key_name=$key_name
EOF
chmod +x ~/deployment/vars
