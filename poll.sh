#!/bin/bash

[ "$REGION" ] || REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
[ "$REGION" ] || REGION=$(aws configure list | grep region | awk '{ print $2 }')

if ! which jq > /dev/null; then
  echo 'jq not installed'
  exit 1
fi

if ! aws --region $REGION ec2 describe-account-attributes > /dev/null 2>&1 < /dev/null; then
  echo 'aws --region $REGION command-line tool not set up correctly'
  exit 1
fi

SECURITY_GROUP="$1"
if [ -z "$SECURITY_GROUP" ]; then
  echo "usage $0 security-group"
  exit 1
fi
shift
PORTS="$@"
if [ -z "$PORTS" ]; then
  PORTS=443
fi
LIST_FILE=cloudfront-ip-ranges-$(date +%Y%m%d%H%M%S).txt
containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}
sync_rules() {
  CURRENT_RULES=$(mktemp)
  if ! aws --region $REGION ec2 describe-security-groups --group-ids $SECURITY_GROUP 2>&1 > $CURRENT_RULES.tmp; then
    echo "Failed to get security group info"
    rm -f $CURRENT_RULES.tmp
    exit 4
  fi
  cat $CURRENT_RULES.tmp | jq -r '.SecurityGroups[0].IpPermissions[]|{Port:.FromPort, CidrIp: .IpRanges[].CidrIp}|"\(.CidrIp):\(.Port)"' 2> /dev/null | sort > $CURRENT_RULES
  rm -f $CURRENT_RULES.tmp
  for rule in $(cat $CURRENT_RULES); do
    CIDR=$(echo $rule | cut -d ":" -f1)
    PORT=$(echo $rule | cut -d ":" -f2)
    if ! grep $CIDR $LIST_FILE > /dev/null || ! containsElement $PORT $PORTS; then
      echo "Cidr range $rule removed"
      if [ -z "$DRY_RUN" ]; then
        aws --region $REGION ec2 revoke-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port $PORT --cidr $rule
      else
        echo "Would run 'aws --region $REGION ec2 revoke-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port $PORT --cidr $rule'"
      fi
    fi
  done
  for rule in $(cat $LIST_FILE); do
    for PORT in $PORTS; do
      if ! grep "$rule:$PORT" $CURRENT_RULES > /dev/null; then
        echo "Cidr range $rule:$PORT missing"
        if [ -z "$DRY_RUN" ]; then
          aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port $PORT --cidr $rule
        else
          echo "Would run 'aws --region $REGION ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port $PORT --cidr $rule'"
        fi
      fi
    done
  done
  rm -f $CURRENT_RULES
}
if ! curl -s --fail https://ip-ranges.amazonaws.com/ip-ranges.json 2> /dev/null > $LIST_FILE.tmp ; then
  echo "Failed to get current ip ranges"
  rm -f $LIST_FILE.tmp
  exit 2
fi
cat $LIST_FILE.tmp | jq '.prefixes[] | select(.service == "CLOUDFRONT") | .ip_prefix' | cut -d'"' -f 2 | sort > $LIST_FILE
rm -f $LIST_FILE.tmp
if [ "$(wc -l $LIST_FILE | cut -d' ' -f 1)0" -lt "100" ]; then
  echo "Less than 10 ip ranges received - probably broken"
  rm -f $LIST_FILE
  exit 3
fi
NEW_MD5=$(md5sum $LIST_FILE | cut -d" " -f 1)
touch current-md5.txt
OLD_MD5=$(cat current-md5.txt)
if [ "$NEW_MD5" != "$OLD_MD5" ] || [ "$FORCE_SYNC" == "yes" ]; then
  echo "Cloudfront IP ranges changed!"
  ######################
  #### DO ELB MAGIC ####
  ######################
  sync_rules
  cat $LIST_FILE
  echo $NEW_MD5 > current-md5.txt
  exit 1
fi
find . -name 'cloudfront-ip-ranges-*' -a -mtime +7 -exec rm {} \;
exit 0
