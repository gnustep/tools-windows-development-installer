# Set CDPATH to . because if you use the 4NT shell and have the CDPATH
# variable set it will lead to problems during the installation
export CDPATH=.

# Set HOMEPATH to something relative to $GNUSTEP_INSTALL_DIR, because
# we want this development environment to be completely
# self-contained
export HOMEPATH=$GNUSTEP_INSTALL_DIR/UserHomes/$USERNAME

# Set GNUSTEP_CONFIG_FILE. In fact, this isn't necessary, but openapp
# and other scripts look at this variable, and we want to prevent bad
# stuff from happening if somehow this is set to the wrong value. So
# there.
export GNUSTEP_CONFIG_FILE=$GNUSTEP_INSTALL_DIR/GNUstep.conf-dev

. $GNUSTEP_INSTALL_DIR/System/Library/Makefiles/GNUstep.sh
