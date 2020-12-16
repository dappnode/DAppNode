# > This script is designed to be run within a travis CI job, on the before_deploy step
# > It will do the following:
#   1. Configure the git user to dappnode
#   2. Correct origin modify tags and push branches
#   3. Remove current tag before creating the v0.X.Y tag.
#   4. Install and run the dappnodesdk
#   5. Compute the next version from the mainnet APM smart contract
#   6. Generate the release files running the dappnodesdk
#   7. Tag release with the correct version

# > How to include the script in a .travis.yml
#   jobs:
#    include:
#      - stage: release
#        before_deploy:
#          - wget -O - https://raw.githubusercontent.com/dappnode/DAppNode/<path-to-script>/before_deploy.sh | bash


echo "Running DAppNode travis CI before_deploy.sh script"
  
# 0. Grab release type (e.g. release/minor)
TYPE=${TRAVIS_TAG##*/}
[ ! "$TYPE" = "release" ] || TYPE="patch"

# 1. Configure the git user to dappnode
git config --global user.email "dappnode@dappnode.io"
git config --global user.name "dappnode"

# 2. Correct origin modify tags and push branches
git remote rm origin
git remote add origin https://user:${GITHUB_TOKEN}@github.com/${TRAVIS_REPO_SLUG}.git

# 3. Remove current tag before creating the v0.X.Y tag. Fail safe, catch errors with ||
echo "Deleting previous tag $TRAVIS_TAG"
git push --delete origin $TRAVIS_TAG || echo "Error deleting previous tag $TRAVIS_TAG from origin"
git tag --delete $TRAVIS_TAG || echo "Error deleting previous tag $TRAVIS_TAG locally"

# 4. Compute the next version from the mainnet APM smart contract
export RELEASE_VERSION=$(dappnodesdk next ${TYPE} -p infura || echo "0.0.1")
export TRAVIS_TAG="v${RELEASE_VERSION}"
echo "NEXT TRAVIS_TAG $TRAVIS_TAG"

# 5. Tag release with the correct version
# (5.) Check if the tag exists, if so delete it. Fail safe, catch errors with ||
if [ $(git tag -l "$TRAVIS_TAG") ]; then export DELETE_TAG=true ; fi
if [ $DELETE_TAG ]; then git push --delete origin $TRAVIS_TAG || echo "Error deleting tag $TRAVIS_TAG from origin" ; fi
if [ $DELETE_TAG ]; then git tag --delete $TRAVIS_TAG || echo "Error deleting tag $TRAVIS_TAG locally" ; fi
# (5.) Tag this commit
git tag $TRAVIS_TAG
# (5.) Return to master.
#      When travis is triggered by a tag this error happens: 
#      > error: pathspec 'master' did not match any file(s) known to git. 
#      A `git fetch` will be run to ensure that the master branch is present
git fetch
git checkout master

echo "Successfully completed DAppNode travis CI before_deploy.sh script"
