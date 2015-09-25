#!/bin/bash -x

if ! which jq > /dev/null; then
  echo 'jq not installed'
  exit 1
fi

if ! aws ec2 describe-account-attributes > /dev/null 2>&1 < /dev/null; then
  echo 'AWS command-line tool not set up correctly'
  exit 1
fi

SECURITY_GROUP="$1"
if [ -z "$SECURITY_GROUP" ]; then
  echo "usage $0 security-group"
  exit 1
fi
LIST_FILE=cloudfront-ip-ranges-$(date +%Y%m%d%H%M%S).txt

sync_rules() {
  CURRENT_RULES=$(mktemp)
  if ! aws ec2 describe-security-groups --group-ids $SECURITY_GROUP 2>&1 > $CURRENT_RULES.tmp; then
    echo "Failed to get security group info"
    rm -f $CURRENT_RULES.tmp
    exit 4
  fi
  cat $CURRENT_RULES.tmp | jq ".SecurityGroups[0].IpPermissions[0].IpRanges[].CidrIp" 2> /dev/null | cut -d'"' -f 2 | sort > $CURRENT_RULES
  rm -f $CURRENT_RULES.tmp
  for rule in $(cat $CURRENT_RULES); do
    if ! grep $rule $LIST_FILE > /dev/null; then
      echo "Cidr range $rule removed"
      aws ec2 revoke-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port 443 --cidr $rule
    fi
  done
  for rule in $(cat $LIST_FILE); do
    if ! grep $rule $CURRENT_RULES > /dev/null; then
      echo "Cidr range $rule missing"
      aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP --protocol tcp --port 443 --cidr $rule
    fi
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
