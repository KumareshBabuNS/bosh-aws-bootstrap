#!/bin/bash -e

bosh_manifest=./bosh.yml

source ~/deployment/vars
var_az=$avz
var_subnet_id=$subnet_id
var_eip=$eip
var_aws_key_id=$(cat ~/.aws/credentials | grep aws_access_key_id | awk '{print $3}')
var_aws_secret_access_key=$(cat ~/.aws/credentials | grep aws_secret_access_key | awk '{print $3}')
var_aws_region=$(cat ~/.aws/config | grep region | awk '{print $3}')
var_key_name=$key_name

echo "Init BOSH"

sed -i -- "s/REP_VAR_AZ/$var_az/g"                                       $bosh_manifest
sed -i -- "s/REP_VAR_SUBNET_ID/$var_subnet_id/g"                         $bosh_manifest
sed -i -- "s/REP_VAR_EIP/$var_eip/g"                                     $bosh_manifest
sed -i -- "s/REP_VAR_AWS_KEY_ID/$var_aws_key_id/g"                       $bosh_manifest
sed -i -- "s~REP_VAR_AWS_SECRET_ACCESS_KEY~$var_aws_secret_access_key~g" $bosh_manifest
sed -i -- "s/REP_VAR_AWS_REGION/$var_aws_region/g"                       $bosh_manifest
sed -i -- "s/REP_VAR_KEY_NAME/$var_key_name/g"                           $bosh_manifest

bosh-init deploy ./bosh-new.yml
bosh target $var_eip
