#!/usr/bin/env bash
set -euo pipefail

############################################
# ACCOUNT + BUCKET ALIASES
############################################

declare -A ACCOUNT_MAP
ACCOUNT_MAP["INSERT_ACCOUNT_1_NICKNAME_OF_REQUESTOR"]="INSERT_AWS_ACCOUNT_1_ID_HERE"
ACCOUNT_MAP["INSERT_ACCOUNT_2_NICKNAME_WHERE_DATA_LIVES"]="INSERT_AWS_ACCOUNT_2_ID_HERE"

declare -A BUCKET_MAP
BUCKET_MAP["bucket-nickname"]="INSERT_DESIRED_S3_BUCKET_NAME_HERE"

############################################
# INPUT
############################################

if [ "$#" -ne 3 ]; then
  echo "Usage:"
  echo "./cross_account_checker.sh INSERT_ACCOUNT_1_NICKNAME_OF_REQUESTOR INSERT_ACCOUNT_2_NICKNAME_WHERE_DATA_LIVES bucket-nickname"
  exit 1
fi

REQUESTER_ACCOUNT=${ACCOUNT_MAP[$1]:-$1}
DATA_ACCOUNT=${ACCOUNT_MAP[$2]:-$2}
BUCKET_NAME=${BUCKET_MAP[$3]:-$3}

############################################
# VALIDATE ACCOUNT
############################################

CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

if [ "$CURRENT_ACCOUNT" != "$REQUESTER_ACCOUNT" ]; then
  echo "ERROR: Must run from requester account ($REQUESTER_ACCOUNT)"
  exit 1
fi

############################################
# HEADER
############################################

echo "=================================================="
echo "S3 BASH EMULATOR"
echo "=================================================="
echo "Requester: $1 ($REQUESTER_ACCOUNT)"
echo "Data Owner: $2 ($DATA_ACCOUNT)"
echo "Bucket: $BUCKET_NAME"
echo ""

############################################
# STEP 1: ASSUME ROLE
############################################

echo "STEP 1: Assume Role..."

ASSUME_OUTPUT=$(aws sts assume-role \
  --role-arn "arn:aws-us-gov:iam::${REQUESTER_ACCOUNT}:role/mitre-databricks-poc-cross-account" \
  --role-session-name "validation" \
  --region us-gov-west-1 \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')

echo "RESULT: PASS"
echo ""

############################################
# STEP 2: ACCESS BUCKET (WITH PROGRESS)
############################################

echo "STEP 2: Access Bucket..."

echo -n "Loading"
for i in {1..40}; do
  echo -n "."
  sleep 0.05
done
echo ""

LIST_OUTPUT=$(aws s3api list-objects-v2 \
  --bucket "$BUCKET_NAME" \
  --region us-gov-west-1 \
  --output json)

echo "RESULT: PASS"
echo ""

############################################
# METRICS
############################################

OBJECT_COUNT=$(echo "$LIST_OUTPUT" | jq '.Contents | length')
TOTAL_BYTES=$(echo "$LIST_OUTPUT" | jq '[.Contents[].Size] | add')
TOTAL_GIB=$(awk "BEGIN {printf \"%.4f\", $TOTAL_BYTES/1024/1024/1024}")

echo "Objects: $OBJECT_COUNT"
echo "Size: $TOTAL_GIB GiB"
echo ""

############################################
# EXPLORER PROMPT
############################################

read -p "Enter S3 Bash Emulator? (y/n): " EXPLORE
if [[ "$EXPLORE" != "y" ]]; then exit 0; fi

CURRENT_PATH=""

echo ""
echo "=================================================="
echo "S3 BASH EMULATOR MODE"
echo "=================================================="
echo "Commands:"
echo "ls       = list folder"
echo "ls -la   = recursive preview"
echo "ls -d    = folder sizes (slow, streaming)"
echo "ls -ds   = sorted folder sizes (slow)"
echo "tree     = show structure"
echo "cd       = change directory"
echo "pwd      = show path"
echo "du       = total size"
echo "cat      = preview file"
echo "exit     = quit"
echo ""
echo "Tip: run 'ls' first, then cd <folder>"
echo ""

############################################
# LOOP
############################################

while true; do

  DISPLAY_PATH="${CURRENT_PATH:-}"
  read -e -p "s3-bash:/${DISPLAY_PATH} > " CMD

  case "$CMD" in

    ##########################################
    # LS (NO PRE, CLEAN)
    ##########################################
    ls)
      aws s3 ls "s3://$BUCKET_NAME/$CURRENT_PATH" \
      | awk '{$1=""; print substr($0,2)}'
      ;;

    ##########################################
    # LS -LA
    ##########################################
    "ls -la")
      aws s3 ls "s3://$BUCKET_NAME/$CURRENT_PATH" --recursive | head -20
      ;;

    ##########################################
    # LS -D (STREAMING)
    ##########################################
    "ls -d")

      printf "%-40s %-12s %-25s\n" "FOLDER" "SIZE (GiB)" "LAST MODIFIED"
      printf "%-40s %-12s %-25s\n" "----------------------------------------" "------------" "-------------------------"

      aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --prefix "$CURRENT_PATH" \
        --delimiter "/" \
        --output json \
      | jq -r '.CommonPrefixes[]?.Prefix' \
      | while read -r folder; do

        echo "Processing: $folder"

        STATS=$(aws s3api list-objects-v2 \
          --bucket "$BUCKET_NAME" \
          --prefix "$folder" \
          --output json)

        SIZE=$(echo "$STATS" | jq '[.Contents[].Size] | add')
        SIZE_GIB=$(awk "BEGIN {printf \"%.4f\", $SIZE/1024/1024/1024}")
        LAST=$(echo "$STATS" | jq -r '[.Contents[].LastModified] | max')

        printf "%-40s %-12s %-25s\n" "$folder" "$SIZE_GIB" "$LAST"

      done
      ;;

    ##########################################
    # LS -DS (SORTED + PROGRESS)
    ##########################################
    "ls -ds")

      echo "Calculating sizes..."

      TEMP_FILE=$(mktemp)

      aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --prefix "$CURRENT_PATH" \
        --delimiter "/" \
        --output json \
      | jq -r '.CommonPrefixes[]?.Prefix' \
      | while read -r folder; do

        echo "Processing: $folder"

        STATS=$(aws s3api list-objects-v2 \
          --bucket "$BUCKET_NAME" \
          --prefix "$folder" \
          --output json)

        SIZE=$(echo "$STATS" | jq '[.Contents[].Size] | add')
        LAST=$(echo "$STATS" | jq -r '[.Contents[].LastModified] | max')

        echo "$SIZE|$folder|$LAST" >> "$TEMP_FILE"

      done

      printf "%-40s %-12s %-25s\n" "FOLDER" "SIZE (GiB)" "LAST MODIFIED"

      sort -nr "$TEMP_FILE" | while IFS="|" read -r size folder last; do
        SIZE_GIB=$(awk "BEGIN {printf \"%.4f\", $size/1024/1024/1024}")
        printf "%-40s %-12s %-25s\n" "$folder" "$SIZE_GIB" "$last"
      done

      rm -f "$TEMP_FILE"
      ;;

    ##########################################
    # TREE
    ##########################################
    tree)
      aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --prefix "$CURRENT_PATH" \
        --output json \
      | jq -r '.Contents[:50][] | .Key'
      ;;

    ##########################################
    # CD
    ##########################################
    cd\ *)
      TARGET=$(echo "$CMD" | cut -d' ' -f2)

      if [[ "$TARGET" == ".." ]]; then
        CURRENT_PATH=$(echo "$CURRENT_PATH" | sed 's|[^/]*/$||')
      else
        CURRENT_PATH="$CURRENT_PATH$TARGET/"
      fi
      ;;

    ##########################################
    # PWD
    ##########################################
    pwd)
      echo "s3://$BUCKET_NAME/$CURRENT_PATH"
      ;;

    ##########################################
    # DU
    ##########################################
    du)
      STATS=$(aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --prefix "$CURRENT_PATH" \
        --output json)

      SIZE=$(echo "$STATS" | jq '[.Contents[].Size] | add')
      SIZE_GIB=$(awk "BEGIN {printf \"%.4f\", $SIZE/1024/1024/1024}")

      echo "Total Size: $SIZE_GIB GiB"
      ;;

    ##########################################
    # CAT
    ##########################################
    cat\ *)
      FILE=$(echo "$CMD" | cut -d' ' -f2)
      aws s3 cp "s3://$BUCKET_NAME/$CURRENT_PATH$FILE" /tmp/viewfile >/dev/null
      head -n 20 /tmp/viewfile || echo "Binary file"
      ;;

    ##########################################
    # EXIT
    ##########################################
    exit|q)
      break
      ;;

    *)
      echo "Unknown command"
      ;;

  esac

done

echo "Done."
