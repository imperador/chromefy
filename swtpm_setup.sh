#!/usr/bin/env bash

#
# swtpm_setup.sh
#
# Authors: Stefan Berger <stefanb@us.ibm.com>
#
# (c) Copyright IBM Corporation 2011,2014,2015.
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# Neither the names of the IBM Corporation nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# echo "UID=$UID EUID=$EUID"

# Dependencies:
#
# - tpm_tools (tpm-tools package with NVRAM utilities)
# - tcsd      (trousers package with tcsd with -c <configfile> option)
# - expect    (expect package)

SWTPM=`type -P swtpm`
if [ -n "$SWTPM" ]; then
    SWTPM="$SWTPM socket"
fi
SWTPM_IOCTL=`type -P swtpm_ioctl`

ECHO=`which echo`
if [ -z "$ECHO" ]; then
    echo "Error: external echo program not found."
    exit 1
fi
UNAME_S="$(uname -s)"

SETUP_CREATE_EK_F=1
SETUP_TAKEOWN_F=2
SETUP_EK_CERT_F=4
SETUP_PLATFORM_CERT_F=8
SETUP_LOCK_NVRAM_F=16
SETUP_SRKPASS_ZEROS_F=32
SETUP_OWNERPASS_ZEROS_F=64
SETUP_STATE_OVERWRITE_F=128
SETUP_STATE_NOT_OVERWRITE_F=256
SETUP_TPM2_F=512
SETUP_ALLOW_SIGNING_F=1024
SETUP_TPM2_ECC_F=2048
SETUP_CREATE_SPK_F=4096
SETUP_DISPLAY_RESULTS_F=8192
SETUP_DECRYPTION_F=16384

# default values for passwords
DEFAULT_OWNER_PASSWORD=ooo
DEFAULT_SRK_PASSWORD=sss

# default configuration file
DEFAULT_CONFIG_FILE="${XDG_CONFIG_HOME:-/etc}/swtpm_setup.conf"

#default PCR banks to activate for TPM 2
DEFAULT_PCR_BANKS="sha1,sha256"

# TPM constants
TPM_NV_INDEX_D_BIT=$((0x10000000))
TPM_NV_INDEX_EKCert=$((0xF000))
TPM_NV_INDEX_PlatformCert=$((0xF002))

TPM_NV_INDEX_LOCK=$((0xFFFFFFFF))

# TPM 2 constants
TPMA_NV_PLATFORMCREATE=$((0x40000000))
TPMA_NV_AUTHWRITE=$((0x4))
TPMA_NV_AUTHREAD=$((0x40000))
TPMA_NV_NO_DA=$((0x2000000))
TPMA_NV_PPWRITE=$((0x1))
TPMA_NV_PPREAD=$((0x10000))
TPMA_NV_OWNERREAD=$((0x20000))
TPMA_NV_POLICY_DELETE=$((0x400))
TPMA_NV_WRITEDEFINE=$((0x2000))

# Use standard EK Cert NVRAM, EK and SRK handles per IWG spec.
# "TCG TPM v2.0 Provisioning Guide"; Version 1.0, Rev 1.0, March 15, 2017
# Table 2
TPM2_NV_INDEX_RSA_EKCert=$((0x01c00002))
TPM2_NV_INDEX_RSA_EKTemplate=$((0x01c00004))
# For ECC follow "TCG EK Credential Profile For TPM Family 2.0; Level 0"
# Specification Version 2.1; Revision 12; 17 August 2018 (Draft)
TPM2_NV_INDEX_ECC_EKCert=$((0x01c0000a))
TPM2_NV_INDEX_ECC_EKTemplate=$((0x01c0000c))
TPM2_NV_INDEX_PlatformCert=$((0x01c08000))

TPM2_EK_HANDLE=$((0x81010001))
TPM2_SPK_HANDLE=$((0x81000001))

# Default logging goes to stderr
LOGFILE=""

TPMLIB_INFO_TPMSPECIFICATION=1
TPMLIB_INFO_TPMATTRIBUTES=2

NB16='\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
NB32=${NB16}${NB16}
NB256=${NB32}${NB32}${NB32}${NB32}${NB32}${NB32}${NB32}${NB32}
# Nonce used for EK creation; 2 bytes length + nonce
NONCE_RSA='\x01\x00'${NB256}
NONCE_RSA_SIZE=256

NONCE_ECC='\x00\x20'${NB32}
NONCE_ECC_SIZE=32

trap "cleanup" SIGTERM EXIT

logit()
{
	if [ -z "$LOGFILE" ]; then
		echo "$@" >&1
	else
		echo "$@" >> $LOGFILE
	fi
}

logit_cmd()
{
	if [ -z "$LOGFILE" ]; then
		eval "$@" >&1
	else
		eval "$@" >> $LOGFILE
	fi
}

logerr()
{
	if [ -z "$LOGFILE" ]; then
		echo "Error: $@" >&2
	else
		echo "Error: $@" >> $LOGFILE
	fi
}

# Get the size of a file
#
# @param1: filename
get_filesize()
{
	case "${UNAME_S}" in
	OpenBSD|FreeBSD|NetBSD|Darwin|DragonFly)
		stat -f%z $1
		;;
	*)
		stat -c%s $1
		;;
	esac
}

# Get a random number given a lower and upper bound
#
# @param1: lower bound
# @param2: upper bound
get_random()
{
	local lower=$1
	local upper=$2

	echo $(( (RANDOM % (upper - lower)) + lower))
}

# Get the TPM specification parameters from the TPM using swtpm_ioctl
get_tpm_parameters()
{
	local json
	local res part arr

	json="$($SWTPM_IOCTL \
		--info $((TPMLIB_INFO_TPMSPECIFICATION |
		          TPMLIB_INFO_TPMATTRIBUTES)) \
		--tcp :$((TPM_PORT+1)) 2>&1)"
	if [ $? -ne 0 ]; then
		logerr "Error: $SWTPM_IOCTL failed: $json"
		return 1
	fi

	for params in \
		's/.*"family":\s*"\([^"]*\)".*/\1/p --tpm-spec-family' \
		's/.*"level":\s*\([0-9\.]*\).*/\1/p --tpm-spec-level' \
		's/.*"revision":\s*\([0-9]*\).*/\1/p --tpm-spec-revision' \
		's/.*"manufacturer":\s*"\([^"]*\)".*/\1/p --tpm-manufacturer' \
		's/.*"model":\s*"\([^"]*\)".*/\1/p --tpm-model' \
		's/.*"version":\s*"\([^"]*\)".*/\1/p --tpm-version';
	do
		arr=($params)
		part=$(echo "$json" | sed -n "${arr[0]}")
		if [ -z "$part" ]; then
			logerr "Error: Could not parse JSON output"
			logerr "       No result from \"echo '$json' | sed -n '${arr[0]}'\""
			return 1
		fi
		res+="${arr[1]} ${part} "
	done

	echo "${res}"

	return 0
}

# Call external program to create certificates
#
# @param1: flags
# @param2: the configuration file to get the external program from
# @parma3: the directory where to write the certificates to
# @param4: the EK as a sequence of hex nunbers
# @param5: the ID of the VM
call_create_certs()
{
	local ret=0

	local flags="$1"
	local configfile="$2"
	local certdir="$3"
	local ek="$4"
	local vmid="$5"

	local logparam tmp
	local params="" cmd

	if [ -n "$vmid" ]; then
		params="$params --vmid \"$vmid\""
	fi

	if [ -n "$LOGFILE" ]; then
		logparam="--logfile $LOGFILE"
	fi

	params="${params} $(get_tpm_parameters)"
	[ $? -ne 0 ] && return 1

	if [ $((flags & SETUP_EK_CERT_F)) -ne 0 ] || \
	   [ $((flags & SETUP_PLATFORM_CERT_F)) -ne 0 ]; then
		if [ -r "$configfile" ]; then
			# The config file contains lines in the format:
			# key = value
			# or with a comment at the end started by #:
			# key = value # comment
			create_certs_tool="$(sed -n 's/\s*create_certs_tool\s*=\s*\([^#]*\).*/\1/p' \
				"$configfile")"

			create_certs_tool_config="$(sed -n 's/\s*create_certs_tool_config\s*=\s*\([^#]*\).*/\1/p' \
				"$configfile")"
			if [ -n "$create_certs_tool_config" ]; then
				params="$params --configfile \"$create_certs_tool_config\""
			fi

			create_certs_tool_options="$(sed -n 's/\s*create_certs_tool_options\s*=\s*\([^#]*\).*/\1/p' \
				"$configfile")"
			if [ -n "$create_certs_tool_options" ]; then
				params="$params --optsfile \"$create_certs_tool_options\""
			fi
		else
			logerr "Could not access config file" \
			       "'$configfile' to get" \
			       "name of certificate tool to invoke."
			return 1
		fi
	fi

	if [ $((flags & SETUP_TPM2_F)) -ne 0 ]; then
		params="$params --tpm2"
	fi

	if [ -n "$create_certs_tool" ]; then
		local fn=$(basename "${create_certs_tool}")

		if [ $((flags & SETUP_EK_CERT_F)) -ne 0 ]; then
			cmd="$create_certs_tool \
				--type ek \
				--ek "$ek" \
				--dir "$certdir" \
				${logparam} ${params}"
			logit "  Invoking: $(echo $cmd | tr -s " ")"
			tmp="$(eval $cmd 2>&1)"
			ret=$?
			logit "$(echo "${tmp}" | sed -e "s/^/$fn: /")"
			if [ $ret -ne 0 ]; then
				logerr "Error running '$cmd'."
				return $ret
			fi
		fi
		if [ $((flags & SETUP_PLATFORM_CERT_F)) -ne 0 ]; then
			cmd="$create_certs_tool \
				--type platform \
				--ek "$ek" \
				--dir "$certdir" \
				${logparam} ${params}"
			logit "  Invoking: $(echo $cmd | tr -s " ")"
			tmp="$(eval $cmd 2>&1)"
			ret=$?
			logit "$(echo "${tmp}" | sed -e "s/^/$fn: /")"
			if [ $ret -ne 0 ]; then
				logerr "Error running '$cmd'."
				return $ret
			fi
		fi
	fi

	return $ret
}

# Start the TPM on a random open port
#
# @param1: full path to the TPM executable to use
# @param2: the directory where the TPM is supposed to write its state to
start_tpm()
{
	local swtpm="$1"
	local swtpm_state="$2"

	local ctr=0 ctr2 ctr3
	local pidfile="${swtpm_state}/.swtpm_setup.pidfile"

	while [ $ctr -lt 100 ]; do
		TPM_PORT=$(get_random 30000 65535)

		rm -f $pidfile &>/dev/null
		$swtpm \
			--flags not-need-init \
			-p $TPM_PORT \
			--tpmstate dir=$swtpm_state \
			--ctrl type=tcp,port=$((TPM_PORT+1)) \
			--pid file=$pidfile \
			2>&1 1>/dev/null &
		SWTPM_PID=$!

		# poll for open port (good) or the process to have
		# disappeared (bad); whatever happens first
		ctr3=0
		while :; do
			kill -0 $SWTPM_PID 2>/dev/null
			if [ $? -ne 0 ]; then
				# process dead; try next socket
				break
			fi

			# pidfile needs to be there for us to know we are
			# testing swtpm's port rather than some other
			# process's
			ctr2=0
			while [ -f ${pidfile} ]; do
			        # test the connection to swtpm
				(exec 100<>/dev/tcp/localhost/$TPM_PORT) 2>/dev/null
				if [ $? -ne 0 ]; then
					if [ $ctr2 -eq 40 ]; then
						stop_tpm
						break
					fi
					sleep 0.05
					let ctr2=ctr2+1
					continue
				fi
				exec 100>&-
				echo "TPM is listening on TCP port $TPM_PORT."
				return 0
			done
			sleep 0.05

			let ctr3=ctr3+1
			# at some point the pid file must appear...
			if [ $ctr3 -eq 40 ] && [ ! -f ${pidfile} ]; then
				stop_tpm
				break
			fi
		done

		let ctr=$ctr+1
	done

	return 1
}

# Stop the TPM by sigalling it with a SIGTERM
stop_tpm()
{
	[ "$SWTPM_PID" != "" ] && kill -SIGTERM $SWTPM_PID
	SWTPM_PID=
}

# Start the TSS for TPM 1.2
start_tcsd()
{
	local TCSD=$1
	local user=$(id -u -n)
	local group=$(id -g -n)
	local ctr=0 ctr2

	export TSS_TCSD_PORT

	TCSD_CONFIG="$(mktemp)"
	TCSD_DATA_DIR="$(mktemp -d)"
	TCSD_DATA_FILE="$(mktemp --tmpdir=$TCSD_DATA_DIR)"

	if [ -z "$TCSD_CONFIG" ] || [ -z "$TCSD_DATA_DIR" ] || \
	   [ -z "$TCSD_DATA_FILE" ]; then
		logerr "Could not create temporary file; TMPDIR=$TMPDIR"
		return 1
	fi

	while [ $ctr -lt 100 ]; do
		TSS_TCSD_PORT=$(get_random 30000 65535)

		cat << EOF >$TCSD_CONFIG
port = $TSS_TCSD_PORT
system_ps_file = $TCSD_DATA_FILE
EOF
		# tcsd requires tss:tss and 0600 on TCSD_CONFIG
		# -> only root can start
		chmod 600 $TCSD_CONFIG
		if [ $(id -u) -eq 0 ]; then
			chown tss:tss $TCSD_CONFIG 2>/dev/null
			chown tss:tss $TCSD_DATA_DIR 2>/dev/null
			chown tss:tss $TCSD_DATA_FILE 2>/dev/null
		fi
		if [ $? -ne 0 ]; then
			logerr "Could not change ownership on $TCSD_CONFIG to ${user}:${group}."
			ls -l $TCSD_CONFIG
			return 1
		fi

		case "$(id -u)" in
		0)
			$TCSD -c $TCSD_CONFIG -e -f 2>&1 1>/dev/null &
			TCSD_PID=$!
			;;
		*)
			# for tss user, use the wrapper
			$TCSD -c $TCSD_CONFIG -e -f 2>&1 1>/dev/null &
			#if [ $? -ne  0]; then
			#	swtpm_tcsd_launcher -c $TCSD_CONFIG -e -f 2>&1 1>/dev/null &
			#fi
			TCSD_PID=$!
			;;
		esac

		# poll for open port (good) or the process to have
		# disappeared (bad); whatever happens first
	        ctr2=0
	        while :; do
			(exec 100<>/dev/tcp/localhost/$TSS_TCSD_PORT) 2>/dev/null
			if [ $? -ne 0 ]; then
				if [ $ctr2 -eq 40 ]; then
					stop_tcsd
					break
				fi
				# check TCSD is still alive and we haven't
				# successfully test some other process's port
				kill -0 $TCSD_PID 2>/dev/null
				if [ $? -ne 0 ]; then
					break
				fi
				# process still alive
				let ctr2=ctr2+1
				sleep 0.05
				continue
			fi
			exec 100>&-
			echo "TSS is listening on TCP port $TSS_TCSD_PORT."
			return 0
		done

		let ctr=$ctr+1
	done

	return 1
}

# Stop the TSS
stop_tcsd()
{
	[ "$TCSD_PID" != "" ] && kill -SIGTERM $TCSD_PID
	TCSD_PID=
}

# Cleanup everything including TPM, TSS, and files we may have created
cleanup()
{
	stop_tpm
	stop_tcsd
	rm -rf "$TCSD_CONFIG" "$TCSD_DATA_FILE" "$TCSD_DATA_DIR"
}

# Read hex data passed to this function via a pipe and convert them to a
# string using od -t x1. The specifics require the use oif a different
# implementation on OpenBSD than on Linux/Cygwin. On the latter systems it
# can be executed more efficiently using only 'od'.
read_hex_data()
{
	case "${UNAME_S}" in
	OpenBSD|FreeBSD|NetBSD|Darwin|DragonFly)
		od -t x1 -A n | tr -s ' ' | tr -d '\n' | sed 's/ $//'
		;;
	*)
		od -t x1 -A n -w2048
		;;
	esac
}

# Send hex data written in a string with each hex number
# written in the form \x<2 hex digits>
# We have to use bash's echo on OpenBSD 6.2.
# We have to use | cat since some versions of echo otherwise
# stop writing data into a socket after the first \x0a.
#
# @param1: The string with hex numbers
send_hex_data()
{
	case "${UNAME_S}" in
	OpenBSD|FreeBSD|NetBSD|Darwin|DragonFly|CYGWIN*)
		echo -en "$1" | cat
		;;
	*)
		# Some Ubuntu Xenial version still needs this
		$ECHO -en "$1"
		;;
	esac
}

# Transfer a request to the TPM and receive the response
#
# @param1: The request to send
tpm_transfer()
{
	exec 100<>/dev/tcp/127.0.0.1/${TPM_PORT}
	send_hex_data "$1" >&100

	read_hex_data <&100
	exec 100>&-
}

# Create an endorsement key
tpm_createendorsementkeypair()
{
	local req rsp exp

	req='\x00\xc1\x00\x00\x00\x36\x00\x00\x00\x78\x38\xf0\x30\x81\x07\x2b'
	req+='\x0c\xa9\x10\x98\x08\xc0\x4B\x05\x11\xc9\x50\x23\x52\xc4\x00\x00'
	req+='\x00\x01\x00\x03\x00\x02\x00\x00\x00\x0c\x00\x00\x08\x00\x00\x00'
	req+='\x00\x02\x00\x00\x00\x00'

	rsp="$(tpm_transfer "${req}")"

	exp=' 00 c4 00 00 01 3a 00 00 00 00'
	if [ "${rsp:0:30}" != "$exp" ]; then
		logerr "TPM_CreateEndorsementKeyPair() failed"
		logerr "     expected: $exp"
		logerr "     received: ${rsp:0:30}"
		return 1
	fi

	echo "${rsp:114:768}" | tr -d " "

	return 0
}

# Initialize the TPM
#
# @param1: the flags
# @param2: the configuration file to get the external program from
# @parma3: the directory where the TPM is supposed to write it state to
# @param4: the TPM owner password to use
# @param5: The SRK password to use
# @param6: The ID of the VM
init_tpm()
{
	local flags="$1"
	local config_file="$2"
	local tpm_state_path="$3"
	local ownerpass="$4"
	local srkpass="$5"
	local vmid="$6"

	# where external app writes certs into
	local certsdir="$tpm_state_path"
	local ek tmp output

	local PLATFORM_CERT_FILE="$certsdir/platform.cert"
	local EK_CERT_FILE="$certsdir/ek.cert"
	local nvramauth="OWNERREAD|OWNERWRITE"

	start_tpm "$SWTPM" "$tpm_state_path"
	if [ $? -ne 0 ]; then
		logerr "Could not start the TPM."
		return 1
	fi

	export TCSD_USE_TCP_DEVICE=1
	export TCSD_TCP_DEVICE_PORT=$TPM_PORT

	output="$(swtpm_bios 2>&1)"
	if [ $? -ne 0 ]; then
		logerr "swtpm_bios failed: $output"
		return 1
	fi

	# Creating EK is simple enough to do without the tcsd
	if [ $((flags & $SETUP_CREATE_EK_F)) -ne 0 ]; then
		ek="$(tpm_createendorsementkeypair)"
		if [ $? -ne 0 ]; then
			logerr "tpm_createendorsementkeypair failed."
			return 1
		fi
		logit "Successfully created EK."

		if [ $((flags & ~$SETUP_CREATE_EK_F)) -eq 0 ]; then
			return 0
		fi
	fi

	# TPM is enabled and activated upon first start

	start_tcsd $TCSD
	if [ $? -ne 0 ]; then
		return 1
	fi

	# temporarily take ownership if an EK was created
	if [  $((flags & $SETUP_CREATE_EK_F)) -ne 0 ] ; then
		local parm_z=""
		local parm_y=""
		if [ $((flags & $SETUP_SRKPASS_ZEROS_F)) -ne 0 ]; then
			parm_z="-z"
		fi
		if [ $((flags & $SETUP_OWNERPASS_ZEROS_F)) -ne 0 ]; then
			parm_y="-y"
		fi
		if [ -n "${parm_y}" ] && [ -n "${parm_z}" ]; then
			tpm_takeownership $parm_z $parm_y &>/dev/null
		else
			if [ -z "$(type -p expect)" ]; then
				logerr "Missing 'expect' tool to take" \
				       "ownership with non-standard password."
				return 1
			fi
			a=$(expect -c "
				set parm_z \"$parm_z\"
				set parm_y \"$parm_y\"
				spawn tpm_takeownership \$parm_z \$parm_y
				if { \$parm_y == \"\" } {
					expect {
						\"Enter owner password:\"
							{ send \"$ownerpass\n\" }
					}
					expect {
						\"Confirm password:\"
							{ send \"$ownerpass\n\" }
					}
				}
				if { \$parm_z == \"\" } {
					expect {
						\"Enter SRK password:\"
							{ send \"$srkpass\n\" }
					}
					expect {
						\"Confirm password:\"
							{ send \"$srkpass\n\" }
					}
				}
				expect eof
				catch wait result
				exit [lindex \$result 3]
			")
		fi
		if [ $? -ne 0 ]; then
			logerr "Could not take ownership of TPM."
			return 1
		fi
		logit "Successfully took ownership of the TPM."
	fi

	# have external program create the certificates now
	call_create_certs "$flags" "$config_file" "$certsdir" "$ek" "$vmid"
	if [ $? -ne 0 ]; then
		return 1
	fi

	# Define NVRAM are for Physical Presence Interface; unfortunately
	# there are no useful write permissions...
	#tpm_nvdefine \
	#	-i $((0x50010000)) \
	#	-p "PPREAD|PPWRITE|WRITEDEFINE" \
	#	-s 6 2>&1 > /dev/null

	if [ $((flags & SETUP_EK_CERT_F)) -ne 0 ] && \
	   [ -r "${EK_CERT_FILE}" ]; then
		output="$(tpm_nvdefine \
			-i $((TPM_NV_INDEX_EKCert|TPM_NV_INDEX_D_BIT)) \
			-p "${nvramauth}" \
			-s $(get_filesize "${EK_CERT_FILE}") 2>&1)"
		if [ $? -ne 0 ]; then
			logerr "Could not create NVRAM area for EK certificate."
			return 1
		fi
		output="$(tpm_nvwrite -i $((TPM_NV_INDEX_EKCert|TPM_NV_INDEX_D_BIT)) \
			  -f "${EK_CERT_FILE}" 2>&1)"
		if [ $? -ne 0 ]; then
			logerr "Could not write EK cert to NVRAM: $output"
			return 1
		fi
		logit "Successfully created NVRAM area for EK certificate."
		rm -f ${EK_CERT_FILE}
	fi

	if [ $((flags & SETUP_PLATFORM_CERT_F)) -ne 0 ] && \
	   [ -r "${PLATFORM_CERT_FILE}" ] ; then
		output="$(tpm_nvdefine \
			-i $((TPM_NV_INDEX_PlatformCert|TPM_NV_INDEX_D_BIT)) \
			-p "${nvramauth}" \
			-s $(get_filesize "${PLATFORM_CERT_FILE}") 2>&1)"
		if [ $? -ne 0 ]; then
			logerr "Could not create NVRAM area for platform" \
			       "certificate."
			return 1
		fi
		output="$(tpm_nvwrite \
			  -i $((TPM_NV_INDEX_PlatformCert|TPM_NV_INDEX_D_BIT)) \
			  -f "$PLATFORM_CERT_FILE" 2>&1)"
		if [ $? -ne 0 ]; then
			logerr "Could not write EK cert to NVRAM: $output"
			return 1
		fi
		logit "Successfully created NVRAM area for platform" \
		       "certificate."
		rm -f ${PLATFORM_CERT_FILE}
	fi

	if [ $((flags & SETUP_DISPLAY_RESULTS_F)) -ne 0 ]; then
		local nvidxs=`tpm_nvinfo -n | grep 0x | gawk '{print $1}'`
		local passparam

		if [ $((flags & $SETUP_OWNERPASS_ZEROS_F)) -ne 0 ]; then
			passparam="-z"
		else
			passparam="--password=$ownerpass"
		fi

		for i in $nvidxs; do
			logit "Content of NVRAM area $i:"
			tmp="tpm_nvread -i $i $passparam"
			logit_cmd "$cmd"
		done
	fi

	# Last thing is to lock the NVRAM area
	if [ $((flags & SETUP_LOCK_NVRAM_F)) -ne 0 ]; then
		output="$(tpm_nvdefine -i $TPM_NV_INDEX_LOCK 2>&1)"
		if [ $? -ne 0 ]; then
			logerr "Could not lock NVRAM access: $output"
			return 1
		fi
		logit "Successfully locked NVRAM access."
	fi

	# give up ownership if not wanted
	if [ $((flags & SETUP_TAKEOWN_F))   -eq 0 -a \
	     $((flags & SETUP_CREATE_EK_F)) -ne 0 ] ; then
		if [ $((flags & $SETUP_OWNERPASS_ZEROS_F)) -ne 0 ]; then
			tpm_clear -z &>/dev/null
		else
			if [ -z "$(type -p expect)" ]; then
				logerr "Missing 'expect' tool to take" \
				       "ownership with non-standard password."
				return 1
			fi
			a=$(expect -c "
				spawn tpm_clear
				expect {
					\"Enter owner password:\" { send \"$ownerpass\n\" }
				}
				expect eof
				catch wait result
				exit [lindex \$result 3]
			")
		fi
		if [ $? -ne 0 ]; then
			logerr "Could not give up ownership of TPM."
			return 1
		fi
		logit "Successfully gave up ownership of the TPM."

		# TPM is now disabled and deactivated; enable and activate it
		stop_tpm
		start_tpm "$SWTPM" "$tpm_state_path"

		if [ $? -ne 0 ]; then
			logerr "Could not re-start TPM."
			return 1
		fi

		TCSD_TCP_DEVICE_PORT=$TPM_PORT
		output="$(swtpm_bios -c)"
		if [ $? -ne 0 ]; then
			logerr "swtpm_bios -c -o failed: $output"
			return 1
		fi
		logit "Successfully enabled and activated the TPM"
	fi

	return 0
}

################################# TPM 2 ##################################

# Get a couple of random numbers from the host and stir the TPM
# RNG with them
#
tpm2_stirrandom()
{
	local req r rsp exp

	# just the header, expecting 0x18 bytes of random data
	req='\x80\x01\x00\x00\x00\x24\x00\x00\x01\x46\x00\x18'
	r=$(dd if=/dev/urandom count=24 bs=1 2>/dev/null | \
	    read_hex_data | sed 's/ /\\x/g')

	rsp="$(tpm_transfer "${req}${r}")"

	exp=' 80 01 00 00 00 0a 00 00 00 00'
	if [ "$rsp" != "$exp" ]; then
		logerr "TPM2_Stirrandom() failed"
		logerr "       expected: $exp"
		logerr "       received: $rsp"
		return 1
	fi

	return 0
}

tpm2_changeeps()
{
	local req rsp exp

	req='\x80\x02\x00\x00\x00\x1b\x00\x00\x01\x24\x40\x00\x00\x0c\x00\x00'
	req+='\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00'

	rsp="$(tpm_transfer "${req}")"

	exp=' 80 02 00 00 00 13 00 00 00 00 00 00 00 00 00 00 01 00 00'
	if [ "$rsp" != "$exp" ]; then
		logerr "TPM2_ChangeEPS() failed"
		logerr "       expected: $exp"
		logerr "       received: $rsp"
		return 1
	fi

	return 0
}

# Create the primary key (EK equivalent)
#
# @param1: flags
# @param2: filename for template
tpm2_createprimary_ek_rsa()
{
	local flags="$1"
	local templatefile="$2"

	local symkeydata keyflags totlen publen off min_exp authpolicy

	if [ $((flags & SETUP_ALLOW_SIGNING_F)) -ne 0 ] && \
	   [ $((flags & SETUP_DECRYPTION_F)) -ne 0 ]; then
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, sign, decrypt
		keyflags=$((0x000600b2))
		# symmetric: TPM_ALG_NULL
		symkeydata='\\x00\\x10'
		publen=$((0x36 + NONCE_RSA_SIZE))
		totlen=$((0x5f + NONCE_RSA_SIZE))
		min_exp=1506
		# offset of length indicator for key
		off=216
	elif [ $((flags & SETUP_ALLOW_SIGNING_F)) -ne 0 ]; then
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, sign
		keyflags=$((0x000400b2))
		# symmetric: TPM_ALG_NULL
		symkeydata='\\x00\\x10'
		publen=$((0x36 + NONCE_RSA_SIZE))
		totlen=$((0x5f + NONCE_RSA_SIZE))
		min_exp=1506
		# offset of length indicator for key
		off=216
	else
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, restricted, decrypt
		keyflags=$((0x000300b2))
		# symmetric: TPM_ALG_AES, 128bit, TPM_ALG_CFB
		symkeydata='\\x00\\x06\\x00\\x80\\x00\\x43'
		publen=$((0x3a + NONCE_RSA_SIZE))
		totlen=$((0x63 + NONCE_RSA_SIZE))
		min_exp=1518
		# offset of length indicator for key
		off=228
	fi

	authpolicy='\\x83\\x71\\x97\\x67\\x44\\x84\\xb3\\xf8\\x1a\\x90\\xcc\\x8d'
	authpolicy+='\\x46\\xa5\\xd7\\x24\\xfd\\x52\\xd7\\x6e\\x06\\x52\\x0b\\x64'
	authpolicy+='\\xf2\\xa1\\xda\\x1b\\x33\\x14\\x69\\xaa'

	# Check the TCG EK Credential Profile doc for TPM 2 for
	# parameters used here

	# TPM_RH_ENDORSEMENT
	tpm2_createprimary_rsa_params '\\x40\\x00\\x00\\x0b' "${keyflags}" \
	    "${symkeydata}" "${publen}" "${totlen}" "${min_exp}" "${off}" \
	    "${authpolicy}" "${templatefile}"
	return $?
}

# Create a storage primary key
#
# @param1: flags
tpm2_createprimary_spk_rsa()
{
	local flags="$1"

	local symkeydata keyflags totlen publen off min_exp

	# keyflags: fixedTPM, fixedParent, sensitiveDataOrigin,
	# userWithAuth, noDA, restricted, decrypt
	keyflags=$((0x00030472))
	# keyflags=$((0x000300b2))
	# symmetric: TPM_ALG_NULL
	symkeydata='\\x00\\x06\\x00\\x80\\x00\\x43'
	publen=$((0x1a + NONCE_RSA_SIZE))
	totlen=$((0x43 + NONCE_RSA_SIZE))
	min_exp=1470
	# offset of length indicator for key
	off=132

	# TPM_RH_OWNER
	tpm2_createprimary_rsa_params '\\x40\\x00\\x00\\x01' "${keyflags}" \
	    "${symkeydata}" "${publen}" "${totlen}" "${min_exp}" "${off}" "" \
	    ""
	return $?
}

function tpm2_createprimary_rsa_params()
{
	local primaryhandle="$1"
	local keyflags="$2"
	local symkeydata="$3"
	local publen="$4"
	local totlen="$5"
	local min_exp="$6"
	local off="$7"
	local authpolicy="$8"
	local templatefile="$9"

	local req rsp res temp
	local authpolicylen=$((${#authpolicy} / 5))

	req='\x80\x02@TOTLEN-4@\x00\x00\x01\x31'
	req+='@KEYHANDLE-4@'
	# size of buffer
	req+='\x00\x00\x00\x09'
	# TPM_RS_PW
	req+='\x40\x00\x00\x09\x00\x00\x00\x00\x00'
	req+='\x00\x04\x00\x00\x00\x00'
	# Size of TPM2B_PUBLIC
	req+='@PUBLEN-2@'
	# TPM_ALG_RSA, TPM_ALG_SHA256
	temp='\x00\x01\x00\x0b'
	# fixedTPM, fixedParent, sensitiveDatOrigin, adminWithPolicy
	# restricted, decrypt
	temp+='@KEYFLAGS-4@'
	# authPolicy;32 bytes
	temp+='@AUTHPOLICYLEN-2@'
	temp+='@AUTHPOLICY@'
	temp+='@SYMKEYDATA@'
	# scheme: TPM_ALG_NULL, keyBits: 2048bits
	temp+='\x00\x10\x08\x00'
	# exponent
	temp+='\x00\x00\x00\x00'
	# TPM2B_DATA
	temp+=${NONCE_RSA}

	temp=$(echo $temp | \
	       sed -e "s/@KEYFLAGS-4@/$(_format "$keyflags" 4)/" \
	           -e "s/@SYMKEYDATA@/$symkeydata/" \
	           -e "s/@AUTHPOLICY@/$authpolicy/" \
	           -e "s/@AUTHPOLICYLEN-2@/$(_format "$authpolicylen" 2)/")

	req+=${temp}
	# TPML_PCR_SELECTION
	req+='\x00\x00\x00\x00\x00\x00'

	req=$(echo $req | \
	      sed -e "s/@PUBLEN-2@/$(_format "$publen" 2)/" \
	          -e "s/@TOTLEN-4@/$(_format "$totlen" 4)/" \
	          -e "s/@KEYHANDLE-4@/$primaryhandle/")

	rsp="$(tpm_transfer "${req}")"

	if [ ${#rsp} -lt $min_exp ]; then
		logerr "TPM2_CreatePrimary(RSA) failed"
		logerr "       expected at least $min_exp bytes, got ${#rsp}."
		logerr "       response: $rsp"
		return 1
	fi

	# Check the RSA modulus length indicator
	if [ "${rsp:$off:6}" != " 01 00" ]; then
		logerr "Getting modulus from wrong offset."
		return 1
	fi

	let off=off+6

	# output: handle,ek
	res="$(echo "0x${rsp:30:12}" | sed -n 's/ //pg'),"
	res+="$(echo "${rsp:$off:768}" | sed -n 's/ //pg')"
	echo $res

	if [ -n "${templatefile}" ]; then
		$ECHO -en ${temp} > ${templatefile}
	fi

	return 0
}

# Create the primary key as an ECC key (EK equivalent)
#
# @param1: flags
# @param2: filename for template
tpm2_createprimary_ek_ecc()
{
	local flags="$1"
	local templatefile="$2"

	local min_exp symkeydata keyflags totlen publen off1 off2 authpolicy

	if [ $((flags & SETUP_ALLOW_SIGNING_F)) -ne 0 ] && \
	   [ $((flags & SETUP_DECRYPTION_F)) -ne 0 ]; then
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, sign, decrypt
		keyflags=$((0x000600b2))
		# symmetric: TPM_ALG_NULL
		symkeydata='\\x00\\x10'
		publen=$((0x36 + 2 * NONCE_ECC_SIZE))
		totlen=$((0x5f + 2 * NONCE_ECC_SIZE))
		min_exp=930
		# offset of length indicator for key
		off1=210
		off2=312
	elif [ $((flags & SETUP_ALLOW_SIGNING_F)) -ne 0 ]; then
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, sign
		keyflags=$((0x000400b2))
		# symmetric: TPM_ALG_NULL
		symkeydata='\\x00\\x10'
		publen=$((0x36 + 2 * NONCE_ECC_SIZE))
		totlen=$((0x5f + 2 * NONCE_ECC_SIZE))
		min_exp=930
		# offset of length indicator for key
		off1=210
		off2=312
	else
		# keyflags: fixedTPM, fixedParent, sensitiveDatOrigin,
		# adminWithPolicy, restricted, decrypt
		keyflags=$((0x000300b2))
		# symmetric: TPM_ALG_AES, 128bit, TPM_ALG_CFB
		symkeydata='\\x00\\x06\\x00\\x80\\x00\\x43'
		publen=$((0x3a + 2 * NONCE_ECC_SIZE))
		totlen=$((0x63 + 2 * NONCE_ECC_SIZE))
		# some version of TPM2 returns 942, another 990
		min_exp=942
		# offset of length indicator for key
		off1=222
		off2=324
	fi

	authpolicy='\\x83\\x71\\x97\\x67\\x44\\x84\\xb3\\xf8\\x1a\\x90\\xcc\\x8d'
	authpolicy+='\\x46\\xa5\\xd7\\x24\\xfd\\x52\\xd7\\x6e\\x06\\x52\\x0b\\x64'
	authpolicy+='\\xf2\\xa1\\xda\\x1b\\x33\\x14\\x69\\xaa'

	tpm2_createprimary_ecc_params '\\x40\\x00\\x00\\x0b' "${keyflags}" \
	    "${symkeydata}" "${publen}" "${totlen}" "${min_exp}" "${off1}" \
	    "${off2}" "${authpolicy}" "${templatefile}"
	return $?
}

# Create primary storage key as an ECC key
#
# @param1: flags
tpm2_createprimary_spk_ecc()
{
	local flags="$1"

	local min_exp symkeydata keyflags totlen publen off1 off2

	# keyflags: fixedTPM, fixedParent, sensitiveDataOrigin,
	# userWithAuth, noDA, restricted, decrypt
	keyflags=$((0x00030472))
	# symmetric: TPM_ALG_AES, 128bit, TPM_ALG_CFB
	symkeydata='\\x00\\x06\\x00\\x80\\x00\\x43'
	publen=$((0x1a + 2 * NONCE_ECC_SIZE))
	totlen=$((0x43 + 2 * NONCE_ECC_SIZE))
	# some version of TPM2 returns 942, another 990
	min_exp=894
	# offset of length indicator for key
	off1=126
	off2=228

	tpm2_createprimary_ecc_params '\\x40\\x00\\x00\\x0b' "${keyflags}" \
	    "${symkeydata}" "${publen}" "${totlen}" "${min_exp}" "${off1}" \
	    "${off2}" "" ""
	return $?
}

tpm2_createprimary_ecc_params()
{
	local primaryhandle="$1"
	local keyflags="$2"
	local symkeydata="$3"
	local publen="$4"
	local totlen="$5"
	local min_exp="$6"
	local off1="$7"
	local off2="$8"
	local authpolicy="$9"
	local templatefile="${10}"

	local req rsp res temp
	local authpolicylen=$((${#authpolicy} / 5))

	# Check the TCG EK Credential Profile doc for TPM 2 for
	# parameters used here

	req='\x80\x02@TOTLEN-4@\x00\x00\x01\x31'
	# TPM_RH_ENDORSEMENT
	req+='@KEYHANDLE-4@'
	# size of buffer
	req+='\x00\x00\x00\x09'
	# TPM_RS_PW
	req+='\x40\x00\x00\x09\x00\x00\x00\x00\x00'
	# TPM2B_SENSITIVE_CREATE
	req+='\x00\x04\x00\x00\x00\x00'
	# Size of TPM2B_PUBLIC
	req+='@PUBLEN-2@'
	# TPM_ALG_ECC, TPM_ALG_SHA256
	temp='\x00\x23\x00\x0b'
	# flags: fixedTPM, fixedParent, sensitiveDatOrigin, adminWithPolicy
	# restricted, decrypt
	temp+='@KEYFLAGS-4@'
	# authPolicy: size = 32 bytes
	# authPolicy;32 bytes
	temp+='@AUTHPOLICYLEN-2@'
	temp+='@AUTHPOLICY@'
	temp+='@SYMKEYDATA@'
	# scheme: TPM_ALG_NULL, curveID: TPM_ECC_NIST_P256
	temp+='\x00\x10\x00\x03'
	# kdf->scheme: TPM_ALG_NULL
	temp+='\x00\x10'
	# TPM2B_DATA for x and y
	temp+=${NONCE_ECC}
	temp+=${NONCE_ECC}

	temp=$(echo $temp | \
	       sed -e "s/@KEYFLAGS-4@/$(_format "$keyflags" 4)/" \
	           -e "s/@SYMKEYDATA@/$symkeydata/" \
	           -e "s/@AUTHPOLICY@/$authpolicy/" \
	           -e "s/@AUTHPOLICYLEN-2@/$(_format "$authpolicylen" 2)/")

	req+=${temp}
	# TPML_PCR_SELECTION
	req+='\x00\x00\x00\x00\x00\x00'

	req=$(echo $req | \
	      sed -e "s/@PUBLEN-2@/$(_format "$publen" 2)/" \
	          -e "s/@TOTLEN-4@/$(_format "$totlen" 4)/" \
	          -e "s/@KEYHANDLE-4@/$primaryhandle/")

	rsp="$(tpm_transfer "${req}")"
	if [ ${#rsp} -lt $min_exp ]; then
		logerr "TPM2_CreatePrimary(ECC) failed"
		logerr "       expected at least $min_exp bytes, got ${#rsp}."
		logerr "       response: $rsp"
		return 1
	fi

	# Check the x and y length indicators
	if [ "${rsp:$off1:6}" != " 00 20" ] || \
	   [ "${rsp:$off2:6}" != " 00 20" ]; then
		logerr "Getting ECC x and y parameter from wrong offset."
		return 1
	fi

	let off1=off1+6
	let off2=off2+6

	# output: handle,ek
	res="$(echo "0x${rsp:30:12}" | sed -n 's/ //pg'),"
	res+="$(echo x=${rsp:$off1:96},y=${rsp:$off2:96} | sed -n 's/ //pg')"
	echo $res

	if [ -n "${templatefile}" ]; then
		$ECHO -en ${temp} > ${templatefile}
	fi

	return 0
}

# Make a object permanent
#
# @param1: the current object handle
# @param2: the permanent object handle
tpm2_evictcontrol()
{
	local trhandle="$1"
	local pmhandle="$2"

	local req rsp exp

	req='\x80\x02\x00\x00\x00\x23\x00\x00\x01\x20'
	req+='\x40\x00\x00\x01'
	req+='@TRHANDLE-4@'
	req+='\x00\x00\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00'
	req+='@PMHANDLE-4@'

	req=$(echo $req | \
	      sed -e "s/@TRHANDLE-4@/$(_format "$trhandle" 4)/" \
	          -e "s/@PMHANDLE-4@/$(_format "$pmhandle" 4)/")

	rsp="$(tpm_transfer "$req")"

	exp=' 80 02 00 00 00 13 00 00 00 00 00 00 00 00 00 00 01 00 00'
	if [ "${rsp}" != "$exp" ]; then
		logerr "TPM2_EvictControl() failed"
		logerr "       expected: $exp"
		logerr "       received: $rsp"
		return 1
	fi

	return 0
}

# Create the EK, either RSA or ECC
#
# @param1: flags
# @param2: non-evict handle, if any
# @param3: filename for EK template
tpm2_create_ek()
{
	local flags="$1"
	local nehandle="$2"
	local ektemplatefile="$3"

	local res handle

	tpm2_stirrandom
	tpm2_changeeps
	[ $? -ne 0 ] && return 1

	if [ $((flags & SETUP_TPM2_ECC_F)) -ne 0 ]; then
		res=$(tpm2_createprimary_ek_ecc "$flags" "${ektemplatefile}")
	else
		res=$(tpm2_createprimary_ek_rsa "$flags" "${ektemplatefile}")
	fi
	[ $? -ne 0 ] && return 1

	handle=$(echo $res | cut -d "," -f1)

	# make key permanent
	if [ -n "$nehandle" ]; then
		tpm2_evictcontrol "$handle" "$nehandle"
		[ $? -ne 0 ] && return 1
	fi

	# ek
	echo $res | cut -d "," -f2-

	return 0
}

# Create the platform key, either RSA or ECC
#
# @param1: flags
# @param2: non-evict handle, if any
tpm2_create_spk()
{
	local flags="$1"
	local nehandle="$2"

	local res handle

	tpm2_stirrandom
	tpm2_changeeps
	[ $? -ne 0 ] && return 1

	if [ $((flags & SETUP_TPM2_ECC_F)) -ne 0 ]; then
		res=$(tpm2_createprimary_spk_ecc "$flags")
	else
		res=$(tpm2_createprimary_spk_rsa "$flags")
	fi

	[ $? -ne 0 ] && return 1

	handle=$(echo $res | cut -d "," -f1)

	# make key permanent
	if [ -n "$nehandle" ]; then
		tpm2_evictcontrol "$handle" "$nehandle"
		[ $? -ne 0 ] && return 1
	fi

	# ek
	echo $res | cut -d "," -f2-

	return 0
}

# Format an integer to a represenation of '\xaa\xbb...'
#
# @param1: the number to format
# @param2: the size of the integer in bytes
_format()
{
	local num="$1"
	local bytes="$2"

	local f r res i

	case $bytes in
	1) f="%02x"; num=$((num & 0xff));;
	2) f="%04x"; num=$((num & 0xffff));;
	4) f="%08x"; num=$((num & 0xffffffff));;
	esac

	r="$(printf $f $num)"
	for ((i = 0; i < ${#r}; i+=2 )); do
		# prepare for usage with sed -> extra backslashes
		res+="\\\x${r:$i:2}"
	done

	echo $res
}

# Define an NVRAM space
#
# @param1: index
# @param2: access attributes/flags for the NVRAM space
# @param3: the size of the NVRAM area
tpm2_nv_define()
{
	local index="$1"
	local flags="$2"
	local size="$3"

	local req rsp exp

	req='\x80\x02\x00\x00\x00\x2d\x00\x00\x01\x2a\x40\x00\x00\x0c\x00\x00'
	req+='\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00\x00\x00\x00\x0e'
	req+='@INDEX-4@\x00\x0b@FLAGS-4@\x00\x00@SIZE-2@'

	req=$(echo $req | \
	      sed -e "s/@INDEX-4@/$(_format "$index" 4)/" \
	          -e "s/@FLAGS-4@/$(_format "$flags" 4)/" \
	          -e "s/@SIZE-2@/$(_format "$size" 2)/")

	rsp="$(tpm_transfer "$req")"

	exp=' 80 02 00 00 00 13 00 00 00 00 00 00 00 00 00 00 01 00 00'
	if [ "$rsp" != "$exp" ]; then
		logerr "TPM2_NV_DefineSpace() failed"
		logerr "       expected: $exp"
		logerr "       received: $rsp"
		return 1
	fi

	return 0
}

# Write the contents of a file into a NVRAM area
#
# @param1: the NVRAM index
# @param2: The name of the file
tpm2_nv_write()
{
	local index="$1"
	local fil="$2"

	local reqhdr reqbdy req rsp datalen data index_f totlen exp
	local rc=0 offset=0 step=1024

	index_f=$(_format "$index" 4)

	reqhdr='\x80\x02@TOTLEN-4@\x00\x00\x01\x37'

	reqbdy='\x40\x00\x00\x0c@INDEX-4@'
	reqbdy+='\x00\x00\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00'
	reqbdy+='@DATALEN-2@@DATA@@OFFSET-2@'

	exp='  80 02 00 00 00 13 00 00 00 00 '
	exp+='00 00 00 00 00 00 01 00 00'

	while :; do
		# read data from file
		data=$(dd bs=1 skip=${offset} count=${step} if=$fil \
		          2>/dev/null| \
	               read_hex_data | \
	               sed -n 's/ /\\\\x/pg')
	        if [ ${#data} -eq 0 ]; then
			# no data -> done
			break
	        fi
	        # data are prepared for usage with sed
	        datalen=$((${#data} / 5))

		req=$(echo ${reqbdy} | \
		      sed -e "s/@INDEX-4@/${index_f}/g" \
		          -e "s/@DATALEN-2@/$(_format $datalen 2)/" \
		          -e "s/@DATA@/${data}/" \
		          -e "s/@OFFSET-2@/$(_format $offset 2)/")
		totlen=$(( (${#req} / 4) + 10))
		req=$(echo ${reqhdr}${req} | \
		      sed -e "s/@TOTLEN-4@/$(_format $totlen 4)/")

		rsp="$(tpm_transfer "$req")"

		if [ "$res" == "$exp" ]; then
			logerr "TPM2_NV_Write() failed"
			logerr "       expected: $exp"
			logerr "       received: $rsp"
			rc=1
			break
		fi

	        let offset=$offset+step
	done

	return $rc
}

# Lockan NVRAM location
#
# @param1: the NVRAM index
tpm2_nv_writelock()
{
	local index="$1"

	local req rsp exp

	req='\x80\x02\x00\x00\x00\x1f\x00\x00\x01\x38'

	req+='\x40\x00\x00\x0c@INDEX-4@'
	req+='\x00\x00\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00'

	req=$(echo $req | \
	      sed -e "s/@INDEX-4@/$(_format "$index" 4)/")

	rsp="$(tpm_transfer "$req")"

	exp=' 80 02 00 00 00 13 00 00 00 00 00 00 00 00 00 00 01 00 00'
	if [ "$rsp" != "$exp" ]; then
		logerr "TPM2_NV_WriteLock() failed"
		logerr "       expected: $exp"
		logerr "       received: $rsp"
		return 1
	fi

	return 0
}

# Get the list of all PCR banks
function tpm2_get_all_pcr_banks()
{
	local all_pcr_banks=""
	local req rsp exp o l count c bank banks

	req='\x80\x01\x00\x00\x00\x16\x00\x00\x01\x7a'
	req+='\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00\x40'

	rsp="$(tpm_transfer "$req")"
	exp=' 80 01 00 00 00 .. 00 00 00 00'
	if ! [[ "${rsp:0:30}" =~ $exp ]]; then
		logerr "TPM2_Get_Capability() failed for getting PCR bank info"
		logerr "      expected: $exp [pattern]"
		logerr "      received: $rsp"
		return 1
	fi

	# read the count byte's lower nibble
	count=${rsp:56:1}
	o=57
	for ((c=0; c<count;c++)); do
		bank=${rsp:o:6}
		case "$bank" in
		" 00 04") banks="$banks,sha1";;
		" 00 0b") banks="$banks,sha256";;
		" 00 0c") banks="$banks,sha384";;
		" 00 0d") banks="$banks,sha512";;
		" 00 12") banks="$banks,sm3-256";;
		*)
			logerr "Unsupported hash algorithm id ${bank}"
			return 1
		esac
		o=$((o + 6))
		l=$((0x${rsp:o+1:2}))
		o=$((o + 3 + l * 3))
	done

	echo "$banks" | sed 's/^,//'
	return 0
}

# Set the intial active set of PCR banks of a TPM 2
#
# @param1: Comma-separated list of PCR banks to activate
# @param2: List of all PCR banks supported by the TPM 2
function tpm2_set_active_pcr_banks()
{
	local pcr_banks="$1"
	local all_pcr_banks="$2"

	local req rsp exp pcr_bank totlen count
	local OIFS="$IFS" active=""

	req='\x80\x02@TOTLEN-4@\x00\x00\x01\x2b'
	req+='\x40\x00\00\x0c'
	req+='\x00\x00\x00\x09\x40\x00\x00\x09\x00\x00\x00\x00\x00'
	req+='@COUNT-4@'

	totlen=31
	count=0

	# enable the ones the user wants
	for pcr_bank in $(echo ${pcr_banks} | tr "," "\n"); do
		# skip if not even available
		! [[ ",${all_pcr_banks}," =~ ",${pcr_bank}," ]] && continue
		case "${pcr_bank}" in
		sha1)    active="sha1,$active";    req+='\x00\x04\x03\xff\xff\xff';;
		sha256)  active="sha256,$active";  req+='\x00\x0b\x03\xff\xff\xff';;
		sha384)  active="sha384,$active";  req+='\x00\x0c\x03\xff\xff\xff';;
		sha512)  active="sha512,$active";  req+='\x00\x0d\x03\xff\xff\xff';;
		sm3-256) active="sm3-256,$active"; req+='\x00\x12\x03\xff\xff\xff';;
		*)
			logerr "Unsupported PCR bank ${pcr_bank}."
			return 1
		esac
		count=$((count + 1))
	done

	if [ -z "$active" ]; then
		logerr "No PCR banks could be allocated." \
		       "None of the selected algorithms are supported."
		return 1
	fi

	# disable the rest
	for pcr_bank in $(echo ${all_pcr_banks} | tr "," "\n"); do
		# skip over those to activate
		[[ ",${pcr_banks}," =~ ",${pcr_bank}," ]] && continue

		case "$pcr_bank" in
		sha1) req+='\x00\x04\x03\x00\x00\x00';;
		sha256) req+='\x00\x0b\x03\x00\x00\x00';;
		sha384) req+='\x00\x0c\x03\x00\x00\x00';;
		sha512) req+='\x00\x0d\x03\x00\x00\x00';;
		sm3-256) req+='\x00\x12\x03\x00\x00\x00';;
		*)
			logerr "Unsupported PCR bank ${pcr_bank}."
			return 1
		esac
		count=$((count + 1))
	done

	totlen=$((totlen + count * 6))

	req=$(echo $req | \
	      sed -e "s/@TOTLEN-4@/$(_format "$totlen" 4)/" \
	          -e "s/@COUNT-4@/$(_format "$count" 4)/")

	rsp="$(tpm_transfer "$req")"

	exp=' 80 02 00 00 00 20 00 00 00 00 00 00 00 0d 01'
	if [ "${rsp:0:45}" != "$exp" ]; then
		logerr "TPM2_PCR_Allocate() failed"
		logerr "        expected: $exp [first few bytes]"
		logerr "        received: $rsp"
		return 1
	fi

	echo "$active" | sed 's/,$//'

	return 0
}

# Shut down the TPM 2 with SU_CLEAR
function tpm2_shutdown
{
	local req rsp exp

	req='\x80\x01\x00\x00\x00\x0c\x00\x00\x01\x45\x00\x00'

	rsp="$(tpm_transfer "$req")"

	exp=' 80 01 00 00 00 0a 00 00 00 00'
	if [ "$rsp" != "$exp" ]; then
		logerr "TPM2_Shutdown(SU_CLEAR) failed"
		logerr "        expected: $exp"
		logerr "        received: $rsp"
		return 1
	fi

	return 0
}

# Initialize the TPM 2
#
# @param1: the flags
# @param2: the configuration file to get the external program from
# @parma3: the directory where the TPM is supposed to write it state to
# @param4: the TPM owner password to use
# @param5: The SRK password to use
# @param6: The ID of the VM
# @param7: The set of PCR banks to activate
init_tpm2()
{
	local flags="$1"
	local config_file="$2"
	local tpm2_state_path="$3"
	local ownerpass="$4"
	local srkpass="$5"
	local vmid="$6"
	local pcr_banks="$7"

	# where external app writes certs into
	local certsdir="$tpm2_state_path"
	local ek tmp output nvindex nxindex_str
	local all_pcr_banks active_pcr_banks

	local PLATFORM_CERT_FILE="$certsdir/platform.cert"
	local EK_CERT_FILE="$certsdir/ek.cert"
	local EK_TEMP_FILE="$certsdir/ektemplate"

	start_tpm "$SWTPM" "$tpm2_state_path"
	if [ $? -ne 0 ]; then
		logerr "Could not start the TPM 2."
		return 1
	fi

	export TCSD_USE_TCP_DEVICE=1
	export TCSD_TCP_DEVICE_PORT=$TPM_PORT

	output="$(swtpm_bios --tpm2 -c -o 2>&1)"
	if [ $? -ne 0 ]; then
		logerr "swtpm_bios failed: $output"
		return 1
	fi

	if [ $((flags & $SETUP_CREATE_SPK_F)) -ne 0 ]; then
		pk=$(tpm2_create_spk "$flags" "${TPM2_SPK_HANDLE}")
		if [ $? -ne 0 ]; then
			logerr "tpm2_create_spk failed"
			return 1
		fi
		logit "Successfully created storage primary key with " \
		      "handle $(printf "0x%08x" ${TPM2_SPK_HANDLE})."
	fi

	if [ $((flags & $SETUP_CREATE_EK_F)) -ne 0 ]; then
		ek=$(tpm2_create_ek "$flags" "${TPM2_EK_HANDLE}" \
		     "${EK_TEMP_FILE}")
		if [ $? -ne 0 ]; then
			logerr "tpm2_create_ek failed"
			return 1
		fi
		logit "Successfully created EK with handle" \
		      "$(printf "0x%08x" ${TPM2_EK_HANDLE})."

		if [ $((flags & SETUP_TPM2_ECC_F)) -eq 0 ]; then
			nvindex=${TPM2_NV_INDEX_RSA_EKTemplate}
		else
			nvindex=${TPM2_NV_INDEX_ECC_EKTemplate}
		fi
		nvindex_str="$(printf "0x%08x" ${nvindex})"

		if [ $((flags & $SETUP_ALLOW_SIGNING_F )) -ne 0 ]; then
			tpm2_nv_define \
				${nvindex} \
				$((TPMA_NV_PLATFORMCREATE | \
				   TPMA_NV_AUTHREAD | \
				   TPMA_NV_OWNERREAD | \
				   TPMA_NV_PPREAD | \
				   TPMA_NV_PPWRITE | \
				   TPMA_NV_NO_DA | \
				   TPMA_NV_WRITEDEFINE)) \
				$(get_filesize "${EK_TEMP_FILE}")
			if [ $? -ne 0 ]; then
				logerr "Could not create NVRAM area ${nvindex_str}" \
				       "for EK template."
				return 1
			fi
			tpm2_nv_write \
				${nvindex} \
				"${EK_TEMP_FILE}"
			if [ $? -ne 0 ]; then
				logerr "Could not write EK template into" \
				       "NVRAM area ${nvindex_str}."
				return 1
			fi
			if [ $((flags & SETUP_LOCK_NVRAM_F)) -ne 0 ]; then
				tpm2_nv_writelock \
					${nvindex}
				if [ $? -ne 0 ]; then
					logerr "Could not lock EK template NVRAM" \
					       "area ${nvindex_str}."
					return 1
				fi
			fi
			logit "Successfully created NVRAM area ${nvindex_str} for EK template."
		fi
		rm -f ${EK_TEMP_FILE}
	fi

	# have external program create the certificates now
	call_create_certs "$flags" "$config_file" "$certsdir" "$ek" "$vmid"
	if [ $? -ne 0 ]; then
		return 1
	fi

	if [ $((flags & SETUP_EK_CERT_F)) -ne 0 ] && \
	   [ -r "${EK_CERT_FILE}" ]; then

		if [ $((flags & SETUP_TPM2_ECC_F)) -eq 0 ]; then
			nvindex=${TPM2_NV_INDEX_RSA_EKCert}
		else
			nvindex=${TPM2_NV_INDEX_ECC_EKCert}
		fi
		nvindex_str="$(printf "0x%08x" ${nvindex})"

		tpm2_nv_define \
			${nvindex} \
			$((TPMA_NV_PLATFORMCREATE | \
			   TPMA_NV_AUTHREAD | \
			   TPMA_NV_OWNERREAD | \
			   TPMA_NV_PPREAD | \
			   TPMA_NV_PPWRITE | \
			   TPMA_NV_NO_DA | \
			   TPMA_NV_WRITEDEFINE)) \
			$(get_filesize "${EK_CERT_FILE}")
		if [ $? -ne 0 ]; then
			logerr "Could not create NVRAM area ${nvindex_str}" \
			       "for EK certificate."
			return 1
		fi
		tpm2_nv_write \
			${nvindex} \
			"${EK_CERT_FILE}"
		if [ $? -ne 0 ]; then
			logerr "Could not write EK certificate into" \
			       "NVRAM area ${nvindex_str}."
			return 1
		fi
		if [ $((flags & SETUP_LOCK_NVRAM_F)) -ne 0 ]; then
			tpm2_nv_writelock \
				${nvindex}
			if [ $? -ne 0 ]; then
				logerr "Could not lock EK certificate NVRAM" \
				       "area ${nvindex_str}."
				return 1
			fi
		fi
		logit "Successfully created NVRAM area ${nvindex_str} for EK certificate."
		rm -f ${EK_CERT_FILE}
	fi

	if [ $((flags & SETUP_PLATFORM_CERT_F)) -ne 0 ] && \
	   [ -r "${PLATFORM_CERT_FILE}" ] ; then

		nvindex=${TPM2_NV_INDEX_PlatformCert}
		nvindex_str="$(printf "0x%08x" ${nvindex})"

		tpm2_nv_define \
			${nvindex} \
			$((TPMA_NV_PLATFORMCREATE | \
			   TPMA_NV_AUTHREAD | \
			   TPMA_NV_OWNERREAD | \
			   TPMA_NV_PPREAD | \
			   TPMA_NV_PPWRITE | \
			   TPMA_NV_NO_DA | \
			   TPMA_NV_WRITEDEFINE)) \
			$(get_filesize "${PLATFORM_CERT_FILE}")
		if [ $? -ne 0 ]; then
			logerr "Could not create NVRAM area ${nvindex_str}" \
			       "for platform certificate."
			return 1
		fi
		tpm2_nv_write \
			${nvindex} \
			"${PLATFORM_CERT_FILE}"
		if [ $? -ne 0 ]; then
			logerr "Could not write platform certificate into" \
			       "NVRAM area ${nvindex_str}."
			return 1
		fi
		if [ $((flags & SETUP_LOCK_NVRAM_F)) -ne 0 ]; then
			tpm2_nv_writelock \
				${nvindex}
			if [ $? -ne 0 ]; then
				logerr "Could not lock platform certificate" \
				       "NVRAM area ${nvindex_str}."
				return 1
			fi
		fi
		logit "Successfully created NVRAM area ${nvindex_str}" \
		      "for platform certificate."
		rm -f ${PLATFORM_CERT_FILE}
	fi

	if [ "$pcr_banks" != "-" ]; then
		all_pcr_banks="$(tpm2_get_all_pcr_banks)"
		[ $? -ne 0 ] && return 1
		active_pcr_banks="$(tpm2_set_active_pcr_banks "$pcr_banks" "$all_pcr_banks")"
		[ $? -ne 0 ] && return 1
		logit "Successfully activated PCR banks $active_pcr_banks among $all_pcr_banks."
	fi

	# FIXME: From here on missing functions...

	if [ $((flags & SETUP_DISPLAY_RESULTS_F)) -ne 0 ]; then
		echo "Display of results not supported yet."
	fi

	tpm2_shutdown
	[ $? -ne 0 ] && return 1

	return 0
}

#################################################################################

# Check whether a TPM state file already exists and whether we are
# allowed to overwrite it or should leave it as is.
#
# @param1: flags
# @param2: the TPM state path (directory)
#
# Return 0 if we can continue, 2 if we should end without an error (state file
# exists and we are not supposed to overwrite it), or 1 if we need to terminate
# with an error
check_state_overwrite()
{
	local flags="$1"
	local tpm_state_path="$2"

	local statefile

	if [ $((flags & SETUP_TPM2_F)) -ne 0 ]; then
		statefile="tpm2-00.permall"
	else
		statefile="tpm-00.permall"
	fi

	if [ -f "${tpm_state_path}/${statefile}" ]; then
		if [ $((flags & SETUP_STATE_NOT_OVERWRITE_F)) -ne 0 ]; then
			logit "Not overwriting existing state file."
			return 2
		fi
		if [ $((flags & SETUP_STATE_OVERWRITE_F)) -ne  0 ]; then
			return 0
		fi
		logerr "Found existing TPM state file ${statefile}."
		return 1
	fi
	return 0
}

versioninfo()
{
	cat <<EOF
TPM emulator setup tool version 0.1.0
EOF
}

usage()
{
	versioninfo
	cat <<EOF

Usage: $1 [options]

The following options are supported:

--runas <user>   : Use the given user id to switch to and run this program;
                   this parameter is interpreted by swtpm_setup that switches
                   to this user and invokes swtpm_setup.sh; defaults to 'tss'

--tpm-state <dir>: Path to a directory where the TPM's state will be written
                   into; this is a mandatory argument

--tpmstate <dir> : This is an alias for --tpm-state <dir>.

--tpm <executable>
                 : Path to the TPM executable; this is an optional argument and
                   by default $SWTPM is used.

--swtpm_ioctl <executable>
                 : Path to the swtpm_ioctl executable; this is an optional
                   argument and by default $SWTPM_IOCTL is used.

--tpm2           : Setup a TPM 2; by default a TPM 1.2 is setup.

--createek       : Create the EK

--allow-signing  : Create an EK that can be used for signing;
                   this option requires --tpm2.

--decryption     : Create an EK that can be used for key encipherment;
                   this is the default unless --allow-signing is given;
                   this option requires --tpm2.

--ecc            : Create ECC keys rather than RSA keys; this requires --tpm2

--take-ownership : Take ownership; this option implies --createek
  --ownerpass  <password>
                 : Provide custom owner password; default is $DEFAULT_OWNER_PASSWORD
  --owner-well-known:
                 : Use an owner password of 20 zero bytes
  --srkpass <password>
                 : Provide custom SRK password; default is $DEFAULT_SRK_PASSWORD
  --srk-well-known:
                 : Use an SRK password of 20 zero bytes
--create-ek-cert : Create an EK certificate; this implies --createek

--create-platform-cert
                 : Create a platform certificate; this implies --create-ek-cert

--create-spk     : Create storage primary key; this requires --tpm2

--lock-nvram     : Lock NVRAM access

--display        : At the end display as much info as possible about the
                   configuration of the TPM

--config <config file>
                 : Path to configuration file; default is $DEFAULT_CONFIG_FILE

--logfile <logfile>
                 : Path to log file; default is logging to stderr

--keyfile <keyfile>
                 : Path to a key file containing the encryption key for the
                   TPM to encrypt its persistent state with. The content
                   must be a 32 hex digit number representing a 128bit AES key.
                   This parameter will be passed to the TPM using
                   '--key file=<file>'.

--pwdfile <pwdfile>
                 : Path to a file containing a passphrase from which the
                   TPM will derive the 128bit AES key. The passphrase can be
                   32 bytes long.
                   This parameter will be passed to the TPM using
                   '--key pwdfile=<file>'.

--cipher <cipher>: The cipher to use; either aes-128-cbc or aes-256-cbc;
                   the default is aes-128-cbc; the same cipher must be
                   used on the swtpm command line

--overwrite      : Overwrite existing TPM state be re-initializing it; if this
                   option is not given, this program will return an error if
                   existing state is detected

--not-overwrite  : Do not overwrite existing TPM state but silently end

--pcr-banks <banks>
                 : Set of PCR banks to activate. Provide a comma separated list
                   like 'sha1,sha256'. '-' to skip and leave all banks active.
                   Default: $DEFAULT_PCR_BANKS

--version        : Display version and exit

--help,-h,-?     : Display this help screen
EOF
}

main()
{
	local flags=0
	local tpm_state_path=""
	local config_file="$DEFAULT_CONFIG_FILE"
	local vmid=""
	local ret
	local keyfile pwdfile cipher="aes-128-cbc"
	local got_ownerpass=0 got_srkpass=0
	local pcr_banks=""

	while [ $# -ne 0 ]; do
		case "$1" in
		--tpm-state|--tpmstate) shift; tpm_state_path="$1";;
		--tpm) shift; SWTPM="$1";;
		--swtpm_ioctl) shift; SWTPM_IOCTL="$1";;
		--tpm2) flags=$((flags | SETUP_TPM2_F));;
		--ecc) flags=$((flags | SETUP_TPM2_ECC_F));;
		--createek) flags=$((flags | SETUP_CREATE_EK_F));;
		--create-spk) flags=$((flags | SETUP_CREATE_SPK_F));;
		--take-ownership) flags=$((flags |
		                   SETUP_CREATE_EK_F|SETUP_TAKEOWN_F));;
		--ownerpass) shift; ownerpass="$1"; got_ownerpass=1;;
		--owner-well-known) flags=$((flags | SETUP_OWNERPASS_ZEROS_F));;
		--srkpass) shift; srkpass="$1"; got_srkpass=1;;
		--srk-well-known) flags=$((flags | SETUP_SRKPASS_ZEROS_F));;
		--create-ek-cert) flags=$((flags |
		                   SETUP_CREATE_EK_F|SETUP_EK_CERT_F));;
		--create-platform-cert) flags=$((flags |
		                   SETUP_CREATE_EK_F|SETUP_PLATFORM_CERT_F));;
		--lock-nvram) flags=$((flags | SETUP_LOCK_NVRAM_F));;
		--display) flags=$((flags | SETUP_DISPLAY_RESULTS_F));;
		--config) shift; config_file="$1";;
		--vmid) shift; vmid="$1";;
		--keyfile) shift; keyfile="$1";;
		--pwdfile) shift; pwdfile="$1";;
		--cipher) shift; cipher="$1";;
		--runas) shift;; # ignore here
		--logfile) shift; LOGFILE="$1";;
		--overwrite) flags=$((flags | SETUP_STATE_OVERWRITE_F));;
		--not-overwrite) flags=$((flags | SETUP_STATE_NOT_OVERWRITE_F));;
		--allow-signing) flags=$((flags | SETUP_ALLOW_SIGNING_F));;
		--decryption) flags=$((flags | SETUP_DECRYPTION_F));;
		--pcr-banks) shift; pcr_banks="${pcr_banks},$1";;
		--version) versioninfo $0; exit 0;;
		--help|-h|-?) usage $0; exit 0;;
		*) logerr "Unknown option $1"; usage $0; exit 1;;
		esac
		shift
	done

	[ $got_ownerpass -eq 0 ] && flags=$((flags | SETUP_OWNERPASS_ZEROS_F))
	[ $got_srkpass -eq 0 ] && flags=$((flags | SETUP_SRKPASS_ZEROS_F))

	pcr_banks="$(echo $pcr_banks |
	             tr -s ',' |
	             sed -e 's/^,//' -e 's/,$//' |
	             tr '[:upper:]' '[:lower:]')"
	[ -z "$pcr_banks" ] && pcr_banks="$DEFAULT_PCR_BANKS"

        # set owner password to default if user didn't provide any password wish
        # and wants to take ownership
	if [ $((flags & SETUP_TAKEOWN_F)) -ne 0 ] && \
	   [ $((flags & SETUP_OWNERPASS_ZEROS_F)) -ne 0 ] && \
	   [ $got_ownerpass -eq 0 ]; then
		ownerpass=$DEFAULT_OWNER_PASSWORD
	fi

        # set SRK password to default if user didn't provide any password wish
        # and wants to take ownership
	if [ $((flags & SETUP_TAKEOWN_F)) -ne 0 ] && \
	   [ $((flags & SETUP_SRKPASS_ZEROS_F)) -ne 0 ] && \
	   [ $got_srkpass -eq 0 ]; then
		srkpass=$DEFAULT_SRK_PASSWORD
	fi

	if [ -n "$LOGFILE" ]; then
		touch $LOGFILE &>/dev/null
		if [ ! -w "$LOGFILE" ]; then
			echo "Cannot write to logfile ${LOGFILE}." >&2
			exit 1
		fi
	fi
	if [ "$tpm_state_path" == "" ]; then
		logerr "--tpm-state must be provided"
		exit 1
	fi
	if [ ! -d "$tpm_state_path" ]; then
		logerr "$tpm_state_path is not a directory that user $(whoami) could access."
		exit 1
	fi

	if [ ! -r "$tpm_state_path" ]; then
		logerr "Need read rights on directory $tpm_state_path for user $(whoami)."
		exit 1
	fi

	if [ ! -w "$tpm_state_path" ]; then
		logerr "Need write rights on directory $tpm_state_path for user $(whoami)."
		exit 1
	fi

	if [ $((flags & SETUP_TPM2_F)) -ne 0 ]; then
		if [ $((flags & SETUP_TAKEOWN_F)) -ne 0 ]; then
			logerr "Taking ownership is not supported for TPM 2."
			exit 1
		fi
	else
		if [ $((flags & SETUP_TPM2_ECC_F)) -ne 0 ]; then
			logerr "--ecc requires --tpm2."
			exit 1
		fi
		if [ $((flags & SETUP_CREATE_SPK_F)) -ne 0 ]; then
			logerr "--create-spk requires --tpm2."
			exit 1
		fi
	fi

        check_state_overwrite "$flags" "$tpm_state_path"
        case $? in
        0) ;;
        1) exit 1;;
        2) exit 0;;
        esac

	rm -f \
		"$tpm_state_path"/*permall \
		"$tpm_state_path"/*volatilestate \
		"$tpm_state_path"/*savestate \
		2>/dev/null
	if [ $? -ne 0 ]; then
		logerr "Could not remove previous state files. Need execute access rights on the directory."
		exit 1
	fi

	if [ -z "$SWTPM" ]; then
		logerr "Default TPM 'swtpm' could not be found and was not provided using --tpm."
		exit 1
	fi

	if [ ! -x "$(echo $SWTPM | cut -d " " -f1)" ]; then
		logerr "TPM at $SWTPM is not an executable."
		exit 1
	fi

	if [ $((flags & SETUP_TPM2_F)) -eq 0 ]; then
		TCSD=`type -P tcsd`
		if [ -z "$TCSD" ]; then
			logerr "tcsd program not found. (PATH=$PATH)"
			exit 1
		fi
		if [ ! -x "$TCSD" ]; then
			logerr "TSS at $TCSD is not an executable."
			exit 1
		fi
	fi

	if [ -z "$SWTPM_IOCTL" ]; then
		logerr "Default 'swtpm_ioctl' could not be found and was not provided using --swtpm_ioctl."
		exit 1
	fi

	if [ ! -x "$(echo $SWTPM_IOCTL | cut -d " " -f1)" ]; then
		logerr "swtpm_ioctl at $SWTPM_IOCTL is not an executable."
		exit 1
	fi

	if [ ! -r "$config_file" ]; then
		logerr "Cannot access config file ${config_file}."
		exit 1
	fi

	if [ -n "$cipher" ]; then
		if ! [[ "$cipher" =~ ^(aes-128-cbc|aes-cbc|aes-256-cbc)$ ]];
		then
			logerr "Unsupported cipher $cipher."
			exit 1
		fi
		cipher=",mode=$cipher"
	fi

	if [ -n "$keyfile" ]; then
		if [ ! -r "$keyfile" ]; then
			logerr "Cannot access keyfile $keyfile."
			exit 1
		fi
		SWTPM="$SWTPM --key file=${keyfile}${cipher}"
		logit "  The TPM's state will be encrypted with a provided key."
	elif [ -n "$pwdfile" ]; then
		if [ ! -r "$pwdfile" ]; then
			logerr "Cannot access passphrase file $pwdfile."
			exit 1
		fi
		SWTPM="$SWTPM --key pwdfile=${pwdfile}${cipher}"
		logit "  The TPM's state will be encrypted using a key derived from a passphrase."
	fi

	# tcsd only runs as tss, so we have to be root or tss here; TPM 1.2 only
	if [ $((flags & SETUP_TPM2_F)) -eq 0 ]; then
		user=$(id -un)
		if [ "$user" != "root" ] && [ "$user" != "tss" ]; then
			logerr "Need to be either root or tss for being able to use tcsd"
			exit 1
		fi
	fi

	logit "Starting vTPM manufacturing as $(id -n -u):$(id -n -g) @ $(date +%c)"

	if [ $((flags & SETUP_TPM2_F)) -eq 0 ]; then
		init_tpm $flags "$config_file" "$tpm_state_path" \
		        "$ownerpass" "$srkpass" "$vmid"
	else
		SWTPM="$SWTPM --tpm2"
		init_tpm2 $flags "$config_file" "$tpm_state_path" \
		        "$ownerpass" "$srkpass" "$vmid" "$pcr_banks"
	fi
	ret=$?
	if [ $ret -eq 0 ]; then
		logit "Successfully authored TPM state."
	else
		logerr "An error occurred. Authoring the TPM state failed."
	fi

	logit "Ending vTPM manufacturing @ $(date +%c)"

	exit $ret
}

main "$@"
