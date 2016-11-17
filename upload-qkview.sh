#!/usr/bin/env bash

# This is a quick script to build diagnostics summaries via the iHealth API.
# [link to dev central wiki]

# These are your iHealth credentials - either fill in the double quotes, or better yet, use environment variables
# during invocation
USER=${USER:-""}
PASS=${PASS:-""}

# This is the path to the cookiefile that curl uses to utilize the inital authentication
COOKIEJAR=/tmp/.cookiefile_${RANDOM}_$$

# set verbose to default on, easy to switch off at runtime
VERBOSE=${VERBOSE:-1}

# Set our data format: json or xml
RESPONSE_FORMAT=${FORMAT:-"xml"}

# location of helper utilities
readonly CURL=/usr/bin/curl

# How many time do we poll the server, and how long do we wait?
readonly POLL_COUNT=100
readonly POLL_WAIT=2
# Shouldn't need to muck with much below here
########################################

CURL_OPTS="-s --user-agent 'showmethemoney' --cookie ${COOKIEJAR} --cookie-jar ${COOKIEJAR} -o /dev/null"
if [[ $DEBUG ]]; then
	CURL_OPTS="--trace-ascii /dev/stderr "${CURL_OPTS}
fi

ACCEPT_HEADER="-H'Accept: application/vnd.f5.ihealth.api+${RESPONSE_FORMAT}'"

function clean {
	if [[ ! $DEBUG ]]; then
		\rm -f ${COOKIEJAR}
	fi
}

function usage {
	echo
	echo "usage: USER=[user] PASS=[pass] <path-to-qkview>"
	echo " - [user] is your iHealth username (email)"
	echo " - [pass] is your iHealth password"
	echo " - OPT: VERBOSE=0 will turn off status messages"
	echo " - OPT: DEBUG=1 will flood you with details"
	echo " - OPT: FORMAT=json will switch responses and processing to be in json"
	echo
	echo "This script will produce a diagnostics summary, and is a companion to"
	echo "an F5 Dev Central article series about the iHealth API [insert link]"

}

function error {
	msg="$1"
	printf "\nERROR: %s\n" "${msg}"
	usage
	clean
	exit 1
}

function xml_extract {
	xml="$1"
	xpath="$2"
	if [[ ! "${xpath}" ]] || [[ "$xpath" = "" ]]; then
		error "Not enough arguments to xml_extract()"
	fi
	cmd=$(printf "echo '%s' | %s select -t -v '%s' -" "${xml}" ${XMLPROCESSOR} "${xpath}")
	echo $(eval ${cmd})
}

function authenticate {
	user="$1"
	pass="$2"
	# Yup!  Security issues here! we're eval'ing with user input.  Don't put this code into a CGI script...
	CURL_CMD="${CURL} --data-ascii \"{\\\"user_id\\\": \\\"${user}\\\", \\\"user_secret\\\": \\\"${pass}\\\"}\" ${CURL_OPTS} -H'Content-type: application/json' -H'Accept: */*' https://api.f5.com/auth/pub/sso/login/ihealth-api"
	[[ $DEBUG ]] && echo ${CURL_CMD}

	if [[ ! "$user" ]] || [[ ! "$pass" ]]; then
		error "missing username or password"
	fi
	eval "$CURL_CMD"
	rc=$?
	if [[ $rc -ne 0 ]]; then
		error "curl authentication request failed with exit code: ${rc}"
	fi

	if ! \grep -e "ssosession" "${COOKIEJAR}" > /dev/null 2>&1; then
		error "Authentication failed, check username and password"
	fi
	[[ $VERBOSE ]] && echo "Authentication successful" >&2
}

function upload_qkview {
	path="$1"
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} -F 'qkview=@${path}' -D /dev/stdout https://ihealth-api.f5.com/qkview-analyzer/api/qkviews"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	out="$(eval "${CURL_CMD}")"
	if [[ $? -ne 0 ]]; then
		error "Couldn't retrieve diagnostics for ${qid}"
	fi
	location=$(echo "${out}" | grep -e '^Location:' | tr -d '\r\n')
	transformed=${location/Location: /}
	echo "${transformed}"
}

function wait_for_state {
	url="$1"
	count=0
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} -w "%{http_code}" ${url}"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	_status=202
	time_passed=0
	while [[ "$_status" -eq 202 ]] && [[ $count -lt ${POLL_COUNT} ]]; do
		_status="$(eval "${CURL_CMD}")"
		count=$((count + 1))
		time_passed=$((count * POLL_WAIT))
		[[ $VERBOSE ]] && echo -ne "waiting (${time_passed} seconds and counting)\r" >&2
		sleep ${POLL_WAIT}
	done
	printf "\nFinished in %s seconds\n" "${time_passed}" >&2
	if [[ "$_status" -eq 200 ]]; then
		[[ $VERBOSE ]] && echo "Success - qkview is ready"
	elif [[ ${count} -ge ${POLL_COUNT} ]]; then
		error "Timed out waiting for qkview to process"
	else
		error "Something went wrong with qkview processing, status: ${_status}"
	fi
}

# Check to see if we got a file path
if [[ ! "$1" ]] || [[ "$1" == '' ]] || [[ ! -f "$1" ]]; then
	error "I need a path to a valid qkview file to continue"
else
	QKVIEW_PATH="$1"
	[[ $VERBOSE -gt 0 ]] && echo "Preparing to upload ${QKVIEW_PATH}"
fi

#Check that we know the response format
if [[ "${RESPONSE_FORMAT}" != 'xml' ]] && [[ "${RESPONSE_FORMAT}" != 'json' ]]; then
	error "$(printf "Response format must be either 'xml' or 'json', '%s' is unknown" "${RESPONSE_FORMAT}")"
fi

# Start fresh
clean

# Auth ourselves
[[ $VERBOSE -gt 0 ]] && echo "Authenticating" >&2
authenticate "${USER}" "${PASS}"

qkview_url="$(upload_qkview "${QKVIEW_PATH}")"

[[ $VERBOSE -gt 0 ]] && echo "Got location of new qkview: ${qkview_url}"

wait_for_state "${qkview_url}"

[[ $VERBOSE ]] && echo "${QKVIEW_PATH} uploaded successfully, see ${qkview_url}"

