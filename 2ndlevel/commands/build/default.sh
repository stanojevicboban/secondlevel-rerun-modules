#!/bin/bash
#
# NAME
#
#   build
#
# DESCRIPTION
#
#   Build the site from install profile.
#

# Parse the command options
[ -r $RERUN_MODULES/2ndlevel/commands/build/options.sh ] && {
  source $RERUN_MODULES/2ndlevel/commands/build/options.sh
}

# Read module function library
[ -r $RERUN_MODULES/2ndlevel/lib/functions.sh ] && {
  source $RERUN_MODULES/2ndlevel/lib/functions.sh
}

# ------------------------------
# Your implementation goes here.
# ------------------------------

set -e

# Install composer before running make, if not already installed
# (Will only work on PHP 5.3+)
drush dl composer-8.x-1.0-alpha3 --no

# Convert to absolute paths
BUILDFILE=`realpath "$BUILDFILE"`
DESTINATION=`realpath "$DESTINATION"`

# Drush make the site structure
echo "Running Drush Make..."
cd `dirname $BUILDFILE` # Must be in dir for drush make's includes[] to work.
cat ${BUILDFILE} | sed "s/^\(projects\[${PROJECT}\].*\)develop$/\1${REVISION}/" | drush make php://stdin ${DESTINATION} \
  --working-copy \
  --prepare-install \
  --no-gitinfofile \
  --prepare-install \
  --yes

chmod u+w ${DESTINATION}/sites/default/settings.php

echo "Appending settings.php snippets..."
for f in ${DESTINATION}/profiles/${PROJECT}/tmp/snippets/*.settings.php
do
  # Concatenate newline and snippet, then append to settings.php
  echo "" | cat - $f | tee -a ${DESTINATION}/sites/default/settings.php > /dev/null
done

tee -a ${DESTINATION}/sites/default/settings.php << 'EOH' > /dev/null

/**
 * Include additional settings files.
 */
$additional_settings = glob(dirname(__FILE__) . '/settings.*.php');
foreach ($additional_settings as $filename) {
  include $filename;
}
EOH

chmod u-w ${DESTINATION}/sites/default/settings.php

# Add snippet that allows basic auth through settings.php
tee -a ${DESTINATION}/.htaccess << 'EOH' > /dev/null

# Required for user/password authentication on development environments.
RewriteEngine on
RewriteRule .* - [E=REMOTE_USER:%{HTTP:Authorization},L]
EOH

# Done
