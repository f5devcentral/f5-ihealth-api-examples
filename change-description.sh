#!/usr/bin/env bash

# This is a quick script to change a qkview description via the iHealth API.
# https://devcentral.f5.com/wiki/ihealth.homepage.ashx
# https://ihealth-api.f5.com/qkview-analyzer/api/docs/index.html

# The source for these scripts is here:
# https://github.com/f5devcentral/f5-ihealth-api-examples

# These are your iHealth credentials - either fill in the double quotes, or better yet, use environment variables
# during invocation
USER=${USER:-""}
PASS=${PASS:-""}

# These are paths to the executables.  Change if needed.
readonly XMLPROCESSOR=/opt/local/bin/xmlstarlet
readonly CURL=/usr/bin/curl
readonly JSONPROCESSOR=/opt/local/bin/jq

# This is the path to the cookiefile that curl uses to utilize the inital authentication
readonly COOKIEJAR=/tmp/.cookiefile_${RANDOM}_$$

# set verbose to default on, easy to switch off at runtime
VERBOSE=${VERBOSE:-1}

# Set our data format: json or xml
readonly RESPONSE_FORMAT=${FORMAT:-"xml"}
# Shouldn't need to muck with much below here
########################################

readonly CURL_OPTS="-s --user-agent 'showmethemoney' --cookie ${COOKIEJAR} --cookie-jar ${COOKIEJAR} -o -"
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
	echo "usage: USER=[user] PASS=[pass] $0 <chassis serial number | hostname>"
	echo " - [user] is your iHealth username (email)"
	echo " - [pass] is your iHealth password"
	echo " - OPT: VERBOSE=0 will turn off status messages"
	echo " - OPT: DEBUG=1 will flood you with details"
	echo " - OPT: FORMAT=json will switch responses and processing to be in json"
	echo
	echo "This script will change the description associated with a qkview,"
	echo "and is a companion to an F5 Dev Central article series about the iHealth"
	echo "API [insert link]"
}

function error {
	msg="$1"
	printf "\nERROR: %s\n" "${msg}"
	usage
	clean
	exit 1
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

function qkview_list {
	CURL_CMD="${CURL}  ${ACCEPT_HEADER} ${CURL_OPTS} https://ihealth-api.f5.com/qkview-analyzer/api/qkviews"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	out="$(eval "${CURL_CMD}")"
	if [[  $? -ne 0 ]]; then
		error "Couldn't retrieve qkview list"
	fi
	echo "${out}"
}

function check_serial {
	qid="$1"
	search_for="$2"
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} https://ihealth-api.f5.com/qkview-analyzer/api/qkviews/${qid}"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	out="$(eval "${CURL_CMD}")"
	if [[  $? -ne 0 ]]; then
		error "Couldn't retrieve qkview metadata for ${qid}"
	fi
	# use format specifier and check serial against search_for
	if [[ $RESPONSE_FORMAT = 'xml' ]]; then
		cs_serial=$(echo $out | ${XMLPROCESSOR} select -t -c "//chassis_serial/node()" -)
	else
		cs_serial=$(echo $out | ${JSONPROCESSOR} -r .chassis_serial -)
	fi
	if [[ "$cs_serial" = "$search_for" ]]; then echo "$cs_serial"; fi
}

function check_hostname {
	qid="$1"
	search_for="$2"
	[[ $DEBUG ]] && echo ${qid} "${search_for}"
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} https://ihealth-api.f5.com/qkview-analyzer/api/qkviews/${qid}/bigip/chassis/hostname"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	out="$(eval "${CURL_CMD}")"
	if [[  $? -ne 0 ]]; then
		error "Couldn't retrieve qkview metadata for ${qid}"
	fi
	# use format specifier and check host against search_for
	if [[ ${RESPONSE_FORMAT} = 'xml' ]]; then
		ch_hostname=$(echo $out | ${XMLPROCESSOR} select -t -c 'bigip/hostname/node()' -)
	else
		ch_hostname=$(echo $out | ${JSONPROCESSOR} -r .bigip.hostname -)
	fi
	if [[ "$ch_hostname" = "$search_for" ]]; then echo "$ch_hostname"; fi
}

function update_description {
	qid="$1"
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} --data-urlencode 'description=${DESCRIPTION}' https://ihealth-api.f5.com/qkview-analyzer/api/qkviews/${qid}"
	out="$(eval "${CURL_CMD}")"
	if [[ $? -ne 0 ]]; then
		error "Couldn't update the description for ${qid}"
	fi
	echo "${out}"
}

function list_count {
	lc_list="$1"
	if [[ ${RESPONSE_FORMAT} = "xml" ]]; then
		count=$(echo ${lc_list} | ${XMLPROCESSOR} select -t -c 'count(//id)' -)
	else
		count=$(echo ${lc_list} | ${JSONPROCESSOR} -r '.id | length' -)
	fi
	echo "$count"
}

function next_qkview_id {
	_index="$1"
	qi_list="$2"
	if [[ ${RESPONSE_FORMAT} = "xml" ]]; then
		qid=$(echo $qi_list | ${XMLPROCESSOR} select -t -v "/qkview_ids/id[${_index}]/node()" -)
	else
		qid=$(echo $qi_list | ${JSONPROCESSOR} -r .id[$_index] -)
	fi
	echo "$qid"
}

# Check to see if we got a hostname or serial
if [[ ! "$1" ]] || [[ "$1" = '' ]]; then
	error "I need a serial number or hostname to continue"
else
	# grab the search term, and remove from args list, as the rest will be
	# the description text
	QKVIEW_SPEC="$1"
	shift
fi
# Check to see if we got any description text
if [[ ! "$1" ]] || [[ "$1" = '' ]]; then
	error "I need some description text"
else
	DESCRIPTION="$*"
	[[ $VERBOSE ]] && echo "Setting description of all qkviews matching ${QKVIEW_SPEC} to '${DESCRIPTION}'"
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

list=$(qkview_list)
count=$(list_count "$list")

if [[ ${RESPONSE_FORMAT} = 'xml' ]]; then
	start_index=1
else
	start_index=0
fi
change_count=0
for ((i=start_index;i<=count;i++)); do
	match_found=0
    qkview_id=$(next_qkview_id $i "$list")

	[[ $VERBOSE ]] && echo "Checking ${qkview_id}" >&2

	hostname=$(check_hostname "${qkview_id}" "${QKVIEW_SPEC}") 

	if [[ "$hostname" ]]; then
		[[ $VERBOSE ]] && printf "Hostname matches -> %s:%s\n" "$hostname" "${QKVIEW_SPEC}" >&2
		match_found=1
	else
		serial=$(check_serial ${qkview_id} "$QKVIEW_SPEC")
		if [[ "$serial" ]]; then
			[[ $VERBOSE ]] && printf "Serial matches -> %s:%s\n" "$serial" "${QKVIEW_SPEC}" >&2
			match_found=1
		fi
	fi

	if [[ $match_found = 1 ]]; then
		[[ $VERBOSE ]] && printf "Updating description for %s to '%s'\n" "${qkview_id}" "${DESCRIPTION}" >&2
		echo "$(update_description "$qkview_id")"
		change_count=$((change_count + 1))
	fi
done

printf "\n\nUpdated ${change_count} qkviews"