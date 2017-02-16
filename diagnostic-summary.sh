#!/usr/bin/env bash

# This is a quick script to build diagnostics summaries via the iHealth API.
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
COOKIEJAR=/tmp/.cookiefile_${RANDOM}_$$

# set verbose to default on, easy to switch off at runtime
VERBOSE=${VERBOSE:-1}

# Set our data format: json or xml
RESPONSE_FORMAT=${FORMAT:-"xml"}
# Shouldn't need to muck with much below here
########################################

CURL_OPTS="-s --user-agent 'showmethemoney' --cookie ${COOKIEJAR} --cookie-jar ${COOKIEJAR} -o -"
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
	echo "usage: USER=[user] PASS=[pass] $0 <qkview_id>"
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

function get_diagnostics_hits {
	qid="$1"
	CURL_CMD="${CURL} ${ACCEPT_HEADER} ${CURL_OPTS} https://ihealth-api.f5.com/qkview-analyzer/api/qkviews/${qid}/diagnostics?set=hit"
	[[ $DEBUG ]] && echo "${CURL_CMD}" >&2
	out="$(eval "${CURL_CMD}")"
	if [[ $? -ne 0 ]]; then
		error "Couldn't retrieve diagnostics for ${qid}"
	fi
	echo "$out"
}

# Check to see if we got a qkview ID
if [[ ! "$1" ]] || [[ "$1" == '' ]]; then
	error "I need a qkview ID to continue"
else
	TARGET_QKVIEW_ID="$1"
	[[ $VERBOSE -gt 0 ]] && echo "Retrieving diagnostics for ${TARGET_QKVIEW_ID}"
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

# Get the diagnostics
diagnostics="$(get_diagnostics_hits "${TARGET_QKVIEW_ID}")"

# Switch processing based on our response format
if [[ ${RESPONSE_FORMAT} = "xml" ]]; then

	#perform some XML extraction, and print it out in a nice readable format
	diagnostics_count=$(echo ${diagnostics} | ${XMLPROCESSOR} select -t -c 'string(/diagnostic_output/diagnostics/@hit_count)' -)
	for ((i=1;i<=diagnostics_count;i++)); do
		printf "%-10s : " $(echo ${diagnostics} | ${XMLPROCESSOR} select -t -c "string(//diagnostic[$i]/@name)" -)
		printf "%s\n" "$(echo ${diagnostics} | ${XMLPROCESSOR} select -t -c "//diagnostic[$i]//h_header/node()" -)"
	done

elif [[ ${RESPONSE_FORMAT} = "json" ]]; then

	# in json
	diagnostics_count=$(echo ${diagnostics} | ${JSONPROCESSOR} -r .diagnostics.hit_count)
	for ((i=0;i<=diagnostics_count;i++)); do
		printf "%-10s : " $(echo ${diagnostics} | ${JSONPROCESSOR} -r .diagnostics.diagnostic[$i].name)
		printf "%s\n" "$(echo ${diagnostics} | ${JSONPROCESSOR} -r .diagnostics.diagnostic[$i].results.h_header)"
	done
fi