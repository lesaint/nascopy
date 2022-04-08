#!/usr/bin/env bash

#
# TODO
# * use SSH remote shell when the source directory is remote
# * enable bash strict mode (set -euo pipefail)
#    * parse input parameters elegantly
#
# DONE
# * remove loop since we can't free any space
# * make files readonly
# * add "--delete" to rsync command to remove files which are now gone
#    * do not delete marker nor inprogress file
#


APPNAME=$(basename $0 | sed "s/\.sh$//")

# -----------------------------------------------------------------------------
# Log functions
# -----------------------------------------------------------------------------

fn_log_info()  { echo "$APPNAME: $1"; }
fn_log_warn()  { echo "$APPNAME: [WARNING] $1" 1>&2; }
fn_log_error() { echo "$APPNAME: [ERROR] $1" 1>&2; }
fn_log_info_cmd()  {
    if [ -n "$SSH_CMD" ]; then
        echo "$APPNAME: $SSH_CMD '$1'";
    else
        echo "$APPNAME: $1";
    fi
}

# -----------------------------------------------------------------------------
# Make sure everything really stops when CTRL+C is pressed and clean PID file
# -----------------------------------------------------------------------------

fn_terminate_script() {
    fn_log_info "SIGINT caught, deleting $PID_FILE and exiting."
    rm -f -- "$PID_FILE"
    exit 1
}

trap 'fn_terminate_script' SIGINT

# -----------------------------------------------------------------------------
# Small utility functions for reducing code duplication
# -----------------------------------------------------------------------------

fn_parse_ssh() {
    if [[ "$DEST_FOLDER" =~ ^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+\:.+$ ]]; then
        SSH_USER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\1/')
        SSH_HOST=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\2/')
        SSH_DEST_FOLDER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\3/')
        SSH_CMD="ssh ${SSH_USER}@${SSH_HOST}"
        SSH_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
    fi
}

fn_run_cmd() {
    if [ -n "$SSH_CMD" ]; then
        eval "$SSH_CMD '$1'"
    else
        eval $1
    fi
}

fn_find() {
    fn_run_cmd "find $1"  2>/dev/null
}

fn_rm() {
    fn_run_cmd "rm -rf -- $1"
}

fn_touch() {
    fn_run_cmd "touch -- $1"
}

fn_chown_all() {
    fn_run_cmd "chown -R -- $1 $2"
}

fn_chmod_dir() {
    local options="$1"
    local target="$2"
    fn_run_cmd "chmod $options -- $target"
}

fn_chmod_all() {
    local options="$1"
    local target="$2"
    fn_run_cmd "chmod -R $options -- $target"
}

# -----------------------------------------------------------------------------
# Source and destination information
# -----------------------------------------------------------------------------
SSH_USER=""
SSH_HOST=""
SSH_DEST_FOLDER=""
SSH_CMD=""
SSH_FOLDER_PREFIX=""

SRC_FOLDER="${1%/}"
DEST_FOLDER="${2%/}"
EXCLUSION_FILE="$3"
OWNER_AND_GROUP="$4"

fn_parse_ssh

if [ -n "$SSH_DEST_FOLDER" ]; then
    DEST_FOLDER="$SSH_DEST_FOLDER"
fi

for ARG in "$SRC_FOLDER" "$DEST_FOLDER" "$EXCLUSION_FILE"; do
    if [[ "$ARG" == *"'"* ]]; then
        fn_log_error 'Arguments may not have any single quote characters.'
        exit 1
    fi
done

# -----------------------------------------------------------------------------
# Handle case where a NAS copy is already running
# -----------------------------------------------------------------------------
PROFILE_FOLDER="$HOME/.$APPNAME"
PID_FILE="$PROFILE_FOLDER/$APPNAME.pid"
MARKER_FILENAME="nascopy.marker"
MARKER_FILE="$DEST_FOLDER/$MARKER_FILENAME"

if [ -f "$PID_FILE" ]; then
    PID="$(cat $PID_FILE)"
    if [ -n "$(ps --pid "$PID" 2>&1 | grep "$PID")" ]; then
        fn_log_error "Previous NAS copy task is still active - aborting."
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Create profile folder if it doesn't exist
# -----------------------------------------------------------------------------

if [ ! -d "$PROFILE_FOLDER" ]; then
    fn_log_info "Creating profile folder in '$PROFILE_FOLDER'..."
    mkdir -- "$PROFILE_FOLDER"
fi

fn_log_info "Creating $PID_FILE"
echo "$$" > "$PID_FILE"

# -----------------------------------------------------------------------------
# Check that the destination drive is a nascopy drive
# -----------------------------------------------------------------------------

fn_find_nascopy_marker() {
    fn_find "$MARKER_FILE" 2>/dev/null
}

if [ -z "$(fn_find_nascopy_marker "$DEST_FOLDER")" ]; then
    fn_log_info "Safety check failed - the destination does not appear to be a NAS copy folder or drive (marker file not found)."
    fn_log_info "If it is indeed a NAS copy folder, you may add the marker file by running the following command:"
    fn_log_info ""
    fn_log_info_cmd "mkdir -p -- \"$DEST_FOLDER\" ; touch \"$MARKER_FILE\""
    fn_log_info ""
    exit 1
fi

# -----------------------------------------------------------------------------
# Setup additional variables
# -----------------------------------------------------------------------------

export IFS=$'\n' # Better for handling spaces in filenames.
INPROGRESS_FILENAME="nascopy.inprogress"
INPROGRESS_FILE="$DEST_FOLDER/$INPROGRESS_FILENAME"


# -----------------------------------------------------------------------------
# Handle case where a previous nascopy failed or was interrupted.
# -----------------------------------------------------------------------------
if [ -n "$(fn_find "$INPROGRESS_FILE")" ]; then
    fn_log_error "NAS Copy already in progress"
    exit 1
fi

# -----------------------------------------------------------------------------
# Fail if destination folder doesn't exists
# -----------------------------------------------------------------------------

if [ -z "$(fn_find "$DEST_FOLDER -type d" 2>/dev/null)" ]; then
    fn_log_error "Destination $SSH_FOLDER_PREFIX$DEST_FOLDER does not exist"
    exit 1
fi

# -----------------------------------------------------------------------------
# Start NAS copy
# -----------------------------------------------------------------------------

LOG_FILE="$PROFILE_FOLDER/$(date +"%Y-%m-%d-%H%M%S").log"

fn_log_info "Starting NAS copy..."
fn_log_info "From: $SRC_FOLDER"
fn_log_info "To:   $SSH_FOLDER_PREFIX$DEST_FOLDER"

CMD="rsync"
if [ -n "$SSH_CMD" ]; then
    CMD="$CMD  -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
fi
CMD="$CMD --compress"
CMD="$CMD --numeric-ids"
CMD="$CMD --safe-links"
CMD="$CMD --hard-links"
CMD="$CMD --one-file-system"
CMD="$CMD --delete"
###     start --archive
CMD="$CMD --recursive"
CMD="$CMD --links"
CMD="$CMD --perms"
CMD="$CMD --times"
#    CMD="$CMD --group"
#    CMD="$CMD --owner"
CMD="$CMD --devices"
CMD="$CMD --specials"
###     end --archive
CMD="$CMD --itemize-changes"
CMD="$CMD --verbose"
CMD="$CMD --human-readable"
CMD="$CMD --log-file '$LOG_FILE'"
CMD="$CMD --exclude '/$INPROGRESS_FILENAME' --exclude '/$MARKER_FILENAME'"
if [ -n "$EXCLUSION_FILE" ]; then
    # We've already checked that $EXCLUSION_FILE doesn't contain a single quote
    CMD="$CMD --exclude-from '$EXCLUSION_FILE'"
fi
CMD="$CMD -- '$SRC_FOLDER/' '$SSH_FOLDER_PREFIX$DEST_FOLDER/'"
CMD="$CMD | grep -E '^deleting|[^/]$'"

fn_log_info "Running command:"
fn_log_info "$CMD"

# give user permission to write in target directory to be able to create inprogress file
fn_chmod_dir "u+w" "$DEST_FOLDER"
fn_touch "$INPROGRESS_FILE"
eval $CMD

# -----------------------------------------------------------------------------
# Check if we ran out of space
# -----------------------------------------------------------------------------

# TODO: find better way to check for out of space condition without parsing log.
NO_SPACE_LEFT="$(grep "No space left on device (28)\|Result too large (34)" "$LOG_FILE")"

if [ -n "$NO_SPACE_LEFT" ]; then
    fn_log_error "No space left on device"
    exit 1
fi

# -----------------------------------------------------------------------------
# Check whether rsync reported any errors
# -----------------------------------------------------------------------------

if [ -n "$(grep "rsync:" "$LOG_FILE")" ]; then
    fn_log_warn "Rsync reported a warning, please check '$LOG_FILE' for more details."
fi
if [ -n "$(grep "rsync error:" "$LOG_FILE")" ]; then
    fn_log_error "Rsync reported an error, please check '$LOG_FILE' for more details."
    exit 1
fi

# -----------------------------------------------------------------------------
# change owner, group and permissions
# -----------------------------------------------------------------------------
if [ -n "$OWNER_AND_GROUP" ]; then
    fn_chown_all "$OWNER_AND_GROUP" "$DEST_FOLDER"
fi

# remove in progress file before we make it readonly
fn_rm "$INPROGRESS_FILE"

# "u=rX,g=-,o=-"
# * u=rX: files are readonly, directories can be opened for user
# * g=-,o=-: group and others have no permissions
fn_chmod_all "u=rX,g=-,o=-" "$DEST_FOLDER"

# -----------------------------------------------------------------------------
# finalize and exit
# -----------------------------------------------------------------------------

fn_log_info "Deleting $PID_FILE"

rm -f -- "$PID_FILE"
rm -f -- "$LOG_FILE"

fn_log_info "NAS copy completed without errors."

exit 0
