# > This script is designed to be run within a travis CI job, on the after_deploy step
# > The will do the following:
#   1. Commit the new versions of the docker-compose.yml and dappnode_package.json
#   2. Create a new branch with the next version number
#   3. Commit the new*new versions of the docker-compose.yml and dappnode_package.json
#   4. Open a pull request to master

# > How to include the script in a .travis.yml
#   jobs:
#    include:
#      - stage: release
#        after_deploy:
#          - wget -O - https://raw.githubusercontent.com/dappnode/DAppNode/<path-to-script>/after_deploy.sh | bash

echo "Running DAppNode travis CI after_deploy.sh script"

# NOTE: git user and remote origin should be already configured from the before script
  
# 1. Commit the new versions of the docker-compose.yml and dappnode_package.json
git add "dappnode_package.json"
git add "docker-compose.yml"
#   Attempt the commit and push. In case of error (no changes), ignore
git commit -m "Update manifest and docker-compose versions to current release: $TRAVIS_TAG" && git push origin || echo "Files are already updated"

# 2. Create a new branch with the next version number
# Check if the dappnodesdk is available
dappnodesdk --help
export FUTURE_VERSION=$(dappnodesdk increase patch)
echo "dappnodesdk increase patch output: $FUTURE_VERSION"
export BRANCH_NAME="v${FUTURE_VERSION}"
echo "Run dappnodesdk and increased version to FUTURE_VERSION: $FUTURE_VERSION"
git checkout -b $BRANCH_NAME

# 3. Commit the new*new versions of the docker-compose.yml and dappnode_package.json
git add "dappnode_package.json"
git add "docker-compose.yml"
git commit -m "Advance manifest and docker-compose versions to new version: $FUTURE_VERSION"
git push origin $BRANCH_NAME

# 4. Open a pull request to master
# It's not straight forward so this step will be skipped by now.

echo "Successfully completed DAppNode travis CI after_deploy.sh script"
