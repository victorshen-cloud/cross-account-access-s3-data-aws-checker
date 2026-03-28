#!/usr/bin/env bash
set -euo pipefail

ROLE_NAME="cross-account-s3-access-role"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
POLICY_NAME="s3-read-policy-$TIMESTAMP"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Requester Account: $ACCOUNT_ID"
echo "Role: $ROLE_NAME"

############################################
# CHECK / CREATE ROLE
############################################

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Role exists. Fetching current trust policy..."
  TRUST_DOC=$(aws iam get-role \
    --role-name "$ROLE_NAME" \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json)
else
  echo "Creating new role..."
  TRUST_DOC='{"Version":"2012-10-17","Statement":[]}'
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_DOC"
fi

############################################
# MERGE TRUST POLICY
############################################

DATA_ACCOUNT_ID="REPLACE_DATA_ACCOUNT_ID"

echo "Merging trust relationship..."

NEW_TRUST=$(echo "$TRUST_DOC" | jq --arg acc "$DATA_ACCOUNT_ID" '
  if (.Statement[]? | select(.Principal.AWS == ("arn:aws:iam::" + $acc + ":root"))) then
    .
  else
    .Statement += [{
      "Effect": "Allow",
      "Principal": { "AWS": ("arn:aws:iam::" + $acc + ":root") },
      "Action": "sts:AssumeRole"
    }]
  end
')

aws iam update-assume-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-document "$NEW_TRUST"

############################################
# CREATE UNIQUE POLICY
############################################

BUCKET="REPLACE_BUCKET"

echo "Creating unique inline policy: $POLICY_NAME"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::$BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::$BUCKET/*"
    }
  ]
}
EOF
)

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOC"

echo "Done."
echo "Role ARN:"
echo "arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
