#!/bin/bash
#
# NAME
#
#   deploy
#
# DESCRIPTION
#
#   Deploy site after building.
#

# Parse the command options
[ -r $RERUN_MODULES/2ndlevel/commands/deploy/options.sh ] && {
  source $RERUN_MODULES/2ndlevel/commands/deploy/options.sh
}

# Read module function library
[ -r $RERUN_MODULES/2ndlevel/lib/functions.sh ] && {
  source $RERUN_MODULES/2ndlevel/lib/functions.sh
}

# ------------------------------
# Your implementation goes here.
# ------------------------------

set -e

BRANCH=develop

# Execute site build script
rerun 2ndlevel:build \
  --build-file $WORKSPACE/profile/build-${PROJECT}.make \
  --destination $WORKSPACE/build \
  --project ${PROJECT}

git clone --branch ${BRANCH} ${REPO} $WORKSPACE/acquia
cd $WORKSPACE/acquia
git rm -r --force --quiet docroot

# rsync build/ dir into acquia repo docroot/
# (excluding files according to patterns in file, accessible to developers.)
rsync --archive --exclude-from=$WORKSPACE/profile/tmp/scripts/docroot-exclude.txt $WORKSPACE/build/ $WORKSPACE/acquia/docroot/
git add --force docroot/

# Sanity check to see what was commited.
git status

# If nothing staged, `git diff --cached` exits with 0
# and so deploy script exits (no error)
if [ "$(git diff --quiet --exit-code --cached; echo $?)" -eq 0 ]; then
  echo 'DEPLOY SCRIPT: No changes staged, and so exiting gracefully...'
  exit 0
fi

# Get commit message from install profile repo and push to $BRANCH
COMMIT_MSG=`git --git-dir=$WORKSPACE/profile/.git log --oneline --max-count=1`
git commit --message="Profile repo commit $COMMIT_MSG"
git push origin ${BRANCH}

# Back up database before running remote drush commands on it.
# We request a backup with the Acquia CLI, and then use the
# task ID to poll for it to be 'done' before moving on.
# We provide output for the logs, and a cap of 10 API calls.

TASK_ID=`drush @${PROJECT}.dev ac-database-backup ${PROJECT} --include=${WORKSPACE}/profile/tmp/scripts --alias-path=${WORKSPACE}/profile/tmp/scripts | awk '{ print $2 }'`

poll_count=0
while [[ "`drush @${PROJECT}.dev ac-task-info $TASK_ID --include=${WORKSPACE}/profile/tmp/scripts --alias-path=${WORKSPACE}/profile/tmp/scripts | grep -E '^ state' | awk '{ print $NF }'`" != "done" ]]
do
  poll_count=`expr $poll_count + 1`
  echo "API polls: $poll_count"
  if [[ "$poll_count" -gt 10 ]]; then
    exit
  fi
  sleep 1
done

# Use drush alias in repo so accessible to developers
drush @${PROJECT}.dev --alias-path=$WORKSPACE/profile/tmp/scripts --yes updatedb
drush @${PROJECT}.dev --alias-path=$WORKSPACE/profile/tmp/scripts --yes fra
drush @${PROJECT}.dev --alias-path=$WORKSPACE/profile/tmp/scripts --yes cc all

# Done
