#!/usr/bin/env bash

# Tomb manager for macOS - Password Store Extension (https://www.passwordstore.org/)
# Based on: https://github.com/roddhjav/pass-tomb
# Copyright (C) 2017 Alex <bendernumber.14@gmail.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# shellcheck disable=SC2181,SC2024

readonly TOMB="${PASSWORD_STORE_TOMB:-mactomb}"
readonly HDIUTIL=/usr/bin/hdiutil
readonly TOMB_PATH="${PASSWORD_STORE_PATH:-$HOME/.password-tomb}"
readonly TOMB_FILE="${TOMB_PATH}/${PASSWORD_STORE_TOMB_FILE:-tomb}"
# readonly TOMB_KEY="${TOMB_PATH}/${PASSWORD_STORE_TOMB_KEY:-tomb.key}"
readonly TOMB_SIZE="${PASSWORD_STORE_TOMB_SIZE:-100}"

readonly _UID="$(id -u "$USER")"
readonly _GID="$(id -g "$USER")"

readonly VERSION="0.1"

#
# Common colors and functions
#
readonly green='\e[0;32m'
readonly yellow='\e[0;33m'
readonly magenta='\e[0;35m'
readonly Bold='\e[1m'
readonly Bred='\e[1;31m'
readonly Bgreen='\e[1;32m'
readonly Byellow='\e[1;33m'
readonly Bblue='\e[1;34m'
readonly Bmagenta='\e[1;35m'
readonly reset='\e[0m'
_message() { [ "$QUIET" = 0 ] && echo -e " ${Bold} . ${reset} ${*}" >&2; }
_warning() { [ "$QUIET" = 0 ] && echo -e " ${Byellow} w ${reset} ${yellow}${*}${reset}" >&2; }
_success() { [ "$QUIET" = 0 ] && echo -e " ${Bgreen}(*)${reset} ${green}${*}${reset}" >&2; }
_error() { echo -e " ${Bred}[x]${reset} ${Bold}Error :${reset} ${*}" >&2; }
_die() { _error "${@}" && exit 1; }
_verbose() { [ "$VERBOSE" = 0 ] || echo -e " ${Bmagenta} . ${reset} ${magenta}pass${reset} ${*}" >&2; }
_verbose_tomb() { [ "$VERBOSE" = 0 ] || echo -e " ${Bmagenta} . ${reset} ${*}" >&2; }

# MARK Validations

# Check program dependencies
#
# pass mtomb depends on mactomb and hdiutil
_ensure_dependencies() {
	command -v "$TOMB" &> /dev/null || _die "Tomb is not present."
    if [ ! -e "${HDIUTIL}" ]; then
        _die "Weird, hdiutil not found in '${HDIUTIL}'. Can't make it."
    fi
}

# Check is provided gpg-id exist in a system
#
# $@ is the list of all the recipient used to encrypt a tomb key
is_valid_recipients() {
	typeset -a recipients
	recipients=($@)

	# All the keys ID must be valid (the public keys must be present in the database)
	for gpg_id in "${recipients[@]}"; do
		gpg --list-keys "$gpg_id" &> /dev/null
		if [[ $? != 0 ]]; then
			_warning "${gpg_id} is not a valid key ID."
			return 1
		fi
	done

	# At least one private key must be present
	for gpg_id in "${recipients[@]}"; do
		gpg --list-secret-keys "$gpg_id" &> /dev/null
		if [[ $? = 0 ]]; then
			return 0
		fi
	done
	return 1
}

# MARK Help

# Print script version
#
cmd_tomb_version() {
	cat <<-_EOF
	$PROGRAM mtomb $VERSION - A pass extension that helps to keep the whole tree of
	                 password encrypted inside a DMG container on macOS.
	_EOF
}

# Print script usage
#
cmd_tomb_usage() {
	cmd_tomb_version
	echo
	cat <<-_EOF
	Usage:
	    $PROGRAM mtomb [-n] [-t time] [-p subfolder] gpg-id...
	        Create and initialise a new password DMG container
	        Use gpg-id for encryption of both DMG and passwords

	    $PROGRAM open [subfolder] [-t time]
	        Open a password DMG container

	    $PROGRAM close [store]
	        Close a password container

	Options:
	    -n, --no-init  Do not initialise the password store
	    -t, --timer    Close the store after a given time
	    -p, --path     Create the store for that specific subfolder
	    -q, --quiet    Be quiet
	    -v, --verbose  Be verbose
	    -d, --debug    Print tomb debug messages
	        --unsafe   Speed up tomb creation (for testing only)
	    -V, --version  Show version information.
	    -h, --help     Print this help message and exit.

	_EOF
}

# MARK Application

# Run mactomb commands
_mtomb() {
	local ii ret
	local cmd="$1"; shift
	"$TOMB" "$cmd" "$@" &> "$TMP"
	ret=$?
	while read -r ii; do
		_verbose_tomb "$ii"
	done <"$TMP"
	[[ $ret == 0 ]] || _die "Unable to ${cmd} the password tomb."
}


# Provide a random filename in shared memory
_tmp_create() {
	local tfile
	tmpdir	# Defines $SECURE_TMPDIR
	tfile="$(mktemp -u "$SECURE_TMPDIR/XXXXXXXXXXXXXXXXXXXX")" # Temporary file

	umask 066
	[[ $? == 0 ]] || _die "Fatal error setting permission umask for temporary files."
	[[ -r "$tfile" ]] && _die "Someone is messing up with us trying to hijack temporary files.";

	touch "$tfile"
	[[ $? == 0 ]] || _die "Fatal error creating temporary file: ${tfile}."

	TMP="$tfile"
	return 0
}

# Set ownership when mounting a tomb
# $1: Tomb path
_set_ownership() {
	local path="$1"
	_verbose "Setting user permissions on ${path}"
	sudo chown -R "${_UID}:${_GID}" "${path}" || _die "Unable to set ownership permission on ${path}."
	sudo chmod 0711 "${path}" || _die "Unable to set permissions on ${path}."
}

# Attach tomb file fo FS
_attach_tomb() {
    local tomb="$1"
    local path="$2"
    ret=$(${HDIUTIL} attach ${tomb} -mountpoint ${path} 2>&1)
	if [[ "$ret" =~ "attach failed" || "$ret" =~ "create canceled" ]]; then
        _error "$ret"
		return 1
	fi
    if [[ "$ret" =~ "${path%?}" ]]; then 
        _verbose "Tomb DMG mouneted"
    fi
    return 0
}

# Detach tomb
_detach_tomb() {
    local path="$1"
    ret=$(${HDIUTIL} detach ${path} 2>&1)
    if [[ "$ret" =~ "ejected." ]]; then
        _verbose "Tomb DMG unmounted"
    fi
    return 0
}

# Open 
cmd_open() {
    local path="$1"; shift;

	# Sanity checks
	check_sneaky_paths "$path" "$TOMB_FILE" 
	[[ -e "${TOMB_FILE}.dmg" ]] || _die "There is no password tomb to open."

	# Open the passwod tomb
	_tmp_create
	_verbose "Opening the password tomb $TOMB_FILE, please insert password"
    _attach_tomb "${TOMB_FILE}.dmg" "${PREFIX}/${path}"
	# _set_ownership "${PREFIX}/${path}"

	# Read, initialise and start the timer
	local timed=1
	if [[ -z "$TIMER" ]]; then
		if [[ -e "${PREFIX}/${path}/.timer" ]]; then
			TIMER="$(cat "${PREFIX}/${path}/.timer")"
			[[ -z "$TIMER" ]] || timed="$(_timer "$TIMER" "${path}")"
		fi
	else
		timed="$(_timer "$TIMER" "${path}")"
	fi

	# Success!
	_success "Your password tomb has been opened in ${PREFIX}/."
	_message "You can now use pass as usual."
	if [[ $timed == 0 ]]; then
		_message "This password store will be closed in $TIMER"
	else
		_message "When finished, close the password tomb using 'pass close'."
	fi
	return 0
}

# Close tomb
cmd_close() {
    local _tomb_name _tomb_file="$1"
	[[ -z "$_tomb_file" ]] && _tomb_file="$TOMB_FILE.dmg"

	# Sanity checks
	check_sneaky_paths "$_tomb_file"
	[[ -e "$_tomb_file" ]] || _die "There is no password tomb to close."
    
	_tomb_name=${_tomb_file##*/}
	_tomb_name=${_tomb_name%.*}
	[[ -z "$_tomb_name" ]] && _die "There is no password tomb."
    
	_tmp_create
	_verbose "Closing the password tomb $_tomb_file"
    
    local res=$("$TOMB" list 2>&1)
    if [[ "$res" =~ "$_tomb_file" ]]; then
        _detach_tomb "${PREFIX}/${path}"
        _success "Your password tomb has been closed."
	    _message "Your passwords remain present in ${_tomb_file}."
    else 
        _message "Nothing to close"
    fi
	return 0
}

# Create a new password tomb and initialise the password repository.
# $1: path subfolder
# $@: gpg-ids
cmd_tomb() {
	local path="$1"; shift;
	typeset -a RECIPIENTS
	[[ -z "$*" ]] && _die "$PROGRAM $COMMAND [-n] [-t time] [-p subfolder] gpg-id..."
	RECIPIENTS=($@)

	# Sanity checks
	check_sneaky_paths "$path" "$TOMB_FILE"
	if ! is_valid_recipients "${RECIPIENTS[@]}"; then
		_die "You set an invalid GPG ID."
	elif [[ -e "$TOMB_KEY" ]]; then
		_die "The tomb key ${TOMB_KEY} already exists. I won't overwrite it."
	elif [[ -e "$TOMB_FILE" ]]; then
		_die "The password tomb ${TOMB_FILE} already exists. I won't overwrite it."
	elif [[ "$TOMB_SIZE" -lt 10 ]]; then
		_die "A password tomb cannot be smaller than 10 MB."
	fi
	if [[ $UNSAFE -ne 0 ]]; then
		_warning "Using unsafe mode to speed up tomb generation."
		_warning "Only use it for testing purposes."
		local unsafe=(--unsafe --use-urandom)
	fi

	# Sharing support
	local recipients_arg tmp_arg
	if [ "${#RECIPIENTS[@]}" -gt 1 ]; then
		tmp_arg="${RECIPIENTS[*]}"
		recipients_arg=${tmp_arg// /,}
	else
		recipients_arg="${RECIPIENTS[0]}"
	fi

	# Create the password tomb
	_tmp_create
    _verbose "Creating a password tomb"
    _message "For now, MacTomb supports only passphrase (symmetric) encryption, but efforts are being made to support both asymmetric encryption and DER certificates."
    _message "This means your tomb password and gpg-id password will be different"
    mkdir -p "$TOMB_PATH"
    _mtomb create -f "$TOMB_FILE" -s "${TOMB_SIZE}m" -n "passtomb"
    _verbose "Mounting tomb DMG to pasword store"
    _attach_tomb "${TOMB_FILE}.dmg" "${PREFIX}/${path}"
    # _set_ownership "${PREFIX}/${path}"

	# Use the same recipients to initialise the password store
	local ret path_cmd=()
	if [[ $NOINIT -eq 0 ]]; then
        _verbose "Init password store with GPG key(s): ${RECIPIENTS[*]}"
		[[ -z "$path" ]] || path_cmd=("--path=${path}")
		ret="$(cmd_init "${RECIPIENTS[@]}" "${path_cmd[@]}")"
		if [[ ! -e "${PREFIX}/${path}/.gpg-id" ]]; then
			_warning "$ret"
			_die "Unable to initialise the password store."
		fi
	fi

	# Initialise the timer
	local timed=1
	[[ -z "$TIMER" ]] || timed="$(_timer "$TIMER" "${path}")"

	# Success!
	_success "Your password tomb has been created and opened in ${PREFIX}."
	[[ -z "$ret" ]] || _success "$ret"
	_message "Your tomb is here: ${TOMB_FILE}"
	# _message "Your tomb key is: ${TOMB_KEY}"
	if [[ -z "$ret" ]]; then
		_message "You need to initialise the store with 'pass init gpg-id...'."
	else
		_message "You can now use pass as usual."
	fi
	if [[ $timed == 0 ]]; then
		_message "This password store will be closed in $TIMER"
	else
		_message "When finished, close the password tomb using 'pass close'."
	fi
	return 0
}

# Check dependencies are present or bail out
_ensure_dependencies

# Global options
UNSAFE=0
VERBOSE=0
QUIET=0
DEBUG=""
NOINIT=0
TIMER=""

# Getopt options
small_arg="vdhVp:qnt:"
long_arg="verbose,debug,help,version,path:,unsafe,quiet,no-init,timer:"
opts="$($GETOPT -o $small_arg -l $long_arg -n "$PROGRAM $COMMAND" -- "$@")"
err=$?
eval set -- "$opts"
while true; do case $1 in
	-q|--quiet) QUIET=1; VERBOSE=0; DEBUG=""; shift ;;
	-v|--verbose) VERBOSE=1; shift ;;
	-d|--debug) DEBUG="-D"; VERBOSE=1; shift ;;
	-h|--help) shift; cmd_tomb_usage; exit 0 ;;
	-V|--version) shift; cmd_tomb_version; exit 0 ;;
	-p|--path) id_path="$2"; shift 2 ;;
	# -t|--timer) TIMER="$2"; shift 2 ;;
	-n|--no-init) NOINIT=1; shift ;;
	--unsafe) UNSAFE=1; shift ;;
	--) shift; break ;;
esac done

[[ $err -ne 0 ]] && cmd_tomb_usage && exit 1
[[ "$COMMAND" == "mtomb" ]] && cmd_tomb "$id_path" "$@"
