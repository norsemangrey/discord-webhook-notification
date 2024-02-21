#!/bin/bash

#### SCRIP USAGE FUNCTION ####

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m, --message <json-content>  The Discord webhook message JSON to be checked."
    echo "  -d, --debug                   Turns on console output"
    echo "  -h, --help                    Show this help message and exit."
    echo ""
    echo "This script will check a Discord webhook message JSON string against content"
    echo "limits set by Discord. The message data must be within the limits in order"
    echo "to be successfully sent. The script will return an exit number based on the"
    echo "results of the check."
    echo ""
    echo " 0) The message data is within the limimts."
    echo " 1) The message data is outside limits, but can be sent in multiple messages."
    echo " 2) The message data is outside limits and cannot be sent."
    echo ""
    echo "Refer to Discord Webook documentation for more details on the webhook limits:"
    echo ""
    echo "  https://birdie0.github.io/discord-webhooks-guide/other/field_limits.html"
    echo ""
}

#### PARSE ARGUMENTS ####

# Parsed from command line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)
            jsonMessage="$2"
            shift 2
            ;;
        -d|--debug)
            debug=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

# Check if JSON is provided and not empty
if [ -z "${jsonMessage}" ]; then
    echo "Error: The --message option is mandatory." >&2
    usage
    exit 2
fi

#### INITIALIZATION & PARAMETERS ####

# Character lenght limits & object count limits (the order is important!)
limits=(
    'Username       .username                   80      char    1'
    'Content        .content                    2000    char    1'
    'Embeds         .embeds                     10      obj     0'
    'Author         .embeds[].author.name       256     char    1'
    'Title          .embeds[].title             256     char    1'
    'Description    .embeds[].description       1024    char    1'
    'Fields         .embeds[].fields            25      obj     1'
    'Name           .embeds[].fields[].name     256     char    1'
    'Value          .embeds[].fields[].value    1024    char    1'
    'Footer         .embeds[].footer.text       2048    char    1'
    'Totals         na                          6000    char    1'
    'Total          na                          6000    char    0'
)

# Set limit parameter names
limitParameters="name section value type critical count"

# Initialize result variables
criticalResult=false
outsideLimits=false
results=""
totalCharactersAllEmbeds=0

#### LIMIT CHECK & RESULTS FUNCTION ####

# Check count against limit and update results
function updateResults() {

    # Output info if debug enabled
    [ ${debug} ] && echo "${name}: ${count}"

    # Compare count with limit value
    if [[ ${count} -gt ${value} ]]; then

        # Set 'outside limit' flag
        outsideLimits=true

        # Check if limit is a critical one
        if [ "${critical}" == "1" ]; then

            # Set 'critical limit' flag
            criticalResult=true

        fi

        # Append to resutl if outside
        results+="${name} ${section} ${value} ${type} ${critical} ${count}\n"

    fi

}

#### CHECK CONTENT ####

# Check content agains each limit
for limit in "${limits[@]}"; do

    # Read parameters from limit
    IFS=' ' read -r $limitParameters <<< "$limit"

    # Check if limit is relates to the embeds section
    if [[ "${section}" == *".embeds[]"* ]]; then

        # Check each embed section individually for applicable limits
        for (( i=0; i<$embedsCount; i++ )); do

            # Get current embed section content
            embed=$(jq -r ".embeds[$i]" <<< "${jsonMessage}")

            # Remove section name parent for correct parsing
            element="${section//'.embeds[]'/}"

            # Check if section is a field section as this is an array
            if [[ "${section}" == *".fields[]"* ]]; then

                # Remove section name parent for correct parsing
                element="${element//'.fields[]'/}"

                # Get the character count sum for each child element of the field section
                count=$(jq ".fields | map($element | length) | add" <<< "${embed}")

            else

                # Get the count (characters or array length)
                count=$(jq "$element | length" <<< "${embed}")

            fi

            # Add to total characters if character type
            [ "${type}" == "char" ] && ((embedTotals[$i]+=count))

            # Check limits and update resutls
            updateResults

        done

    elif [[ "${name}" == "Totals" ]]; then

        # Read the total character count for each embed section
        for count in "${embedTotals[@]}"; do

            # Check agains limit and update result
            updateResults

            # Add to the overall total character count
            ((totalCharactersAllEmbeds+=count))

        done

    #
    elif [[ "${name}" == "Total" ]]; then

        # Get the total character count for all embeds
        count=${totalCharactersAllEmbeds}

        # Check agains limit and update result
        updateResults

    else

        # Get the count (characters or array length)
        count=$(jq "$section | length" <<< "${jsonMessage}")

        # Check if the limit is for the embeds section
        if [[ "${name}" == "Embeds" ]]; then

            # Set the number of embeds (used in other limit check)
            embedsCount=${count}

            # Initialize an array for the character count in each embed
            for (( i=0; i<$embedsCount; i++ )); do

                embedTotals[$i]=0

            done

        fi

        # Check agains limit and update result
        updateResults

    fi


done

#### RETURN RESULTS ####

# Output results
[ ${debug} ] && [ -n "${results}" ] && echo -e "${results%??}"


# Exit with appropriate status
if ${criticalResult}; then

    exit 2

elif ${outsideLimits}; then

    exit 1

else

    exit 0

fi