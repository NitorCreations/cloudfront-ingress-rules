# cloudfront-ingress-rules #

This is a script for synchronizing the ingress rules of a security-group with
the ip ranges of CloudFront from https://ip-ranges.amazonaws.com/ip-ranges.json

## Motivation ##

The script allows you to have a origin domain in CloudFront that only accepts
connections from CloudFront. This means that attackers can't access your
(potentially small - like t2.micro instance) origin node. CloudFront can also
strip HTTP methods, cookies and query strings eliminating lots of attack vectors
if you can guarantee that CloudFront is the only way in. All of the above also
improve caching.

## Intended use ##

We use the script in a Jenkins job that is scheduled to run every 5 minutes. The
scripts returns non-zero if anything goes wrong or if the ranges change, so you
have a chance to check that the rules are all good after IP ranges change. For
example this script will not change your AWS account until the rules change,
so you may be unaware the amazon CLI doesn't work before it tries to make
a change. Our Jenkins job sends an email on failure, so administrators will be able
to react.

## Dependencies ##

The script requires that the AWS command-line tool is installed and the account
is set up. The other uncommon dependency is 'jq' the JSON command-line processing
tool. The script checks for availability and will exit on errors. Jq should be
easily available from most Linux application repositories and aws has instructions
for their cli tool: http://docs.aws.amazon.com/cli/latest/userguide/installing.html
