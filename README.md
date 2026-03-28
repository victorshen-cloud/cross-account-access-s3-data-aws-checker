# cross-account-access-s3-data-aws-checker


A CLI tool for validating and interactively exploring cross-account Amazon S3 access using IAM role assumption.

This tool provides a **Linux-like shell experience on top of S3**, enabling engineers to navigate, inspect, and analyze datasets across AWS accounts without copying data.

----------
### Features

-   Cross-account IAM role validation
-   S3 access verification (List + Read)
-   Interactive “S3 Bash Emulator”
-   Filesystem-like navigation:
    -   `ls`, `cd`, `pwd`
-   Data inspection:
    -   `du` (size)
    -   `ls -d` (folder stats)
    -   `ls -ds` (sorted datasets by size)
    -   `tree` (structure view)
-   Streaming progress for large datasets
-   No data movement — read-only access
----------
### Architecture
[Requester Account]  
                |  
  AssumeRole (STS)  
               |
         [IAM Role]  
                |  
  s3:ListBucket / s3:GetObject  
                 |  
[Data Account S3 Bucket]

-   Data remains in the **data account**
-   Access is granted via **IAM role + bucket policy**
-   No duplication of datasets
----------

### Usage

chmod  +x cross_account_checker.sh  
./cross_account_checker.sh <requester> <data_account> <bucket>

Example:
./cross_account_checker.sh requester-account data-account my-data-bucket

----------

### Interactive Mode
s3-bash:/ >

**Command Descriptions:**

ls -- List folder
ls -la --Recursive preview
ls -d --Folder sizes
ls -ds --Sorted folder sizes
tree --Structure view
cd --Navigate
pwd --Current path
du --Folder size
cat --Preview file

----------
### Security Model

-   Least-privilege IAM role
-   Bucket policy restricts access to specific role
-   Supports external ID (optional)
-   Read-only access by default

----------

### Setup (High Level)

1.  Create IAM role in requester account
2.  Attach S3 read policy
3.  Add bucket policy in data account
4.  Run tool to validate

----------

### Notes

-   Folder sizes are computed dynamically (S3 has no native folder metadata)
-   Large buckets may result in slower `ls -d` operations
-   Designed for GovCloud and standard AWS environments
