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

# shellcheck disable=SC2068,SC1090

if [[ -x "${PASSWORD_STORE_EXTENSIONS_DIR}/mtomb.bash" ]]; then
	source "${PASSWORD_STORE_EXTENSIONS_DIR}/mtomb.bash"
elif [[ -x "${SYSTEM_EXTENSION_DIR}/mtomb.bash" ]]; then
	source "${SYSTEM_EXTENSION_DIR}/mtomb.bash"
else
	die "Unable to load the pass tomb extension."
fi

cmd_close "$@"
