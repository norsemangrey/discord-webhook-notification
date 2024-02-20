#!/usr/bin/bash

# Get path to where script is located.
scriptPath=$(echo "${0%/*}")

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --content <content>   Set the content of the Discord message."
    echo "  -e, --embeds <embeds>     Set the embeds of the Discord message."
    echo "  -h, --help                Show this help message and exit."
    echo ""
    echo "Refer to the Discord documentation for more information on Webhooks"
    echo ""
    echo "  https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks"
    echo ""
}


# Character lenght limits & object count limits
limits=(
    'Content        .content                    2000    char'
    'Embeds         .embeds                     10      obj'
    'Author         .embeds[].author.name       256     char'
    'Title          .embeds[].title             256     char'
    'Description    .embeds[].description       100     char'
    'Fields         .embeds[].fields            25      obj'
    'Name           .embeds[].fields[].name     256     char'
    'Value          .embeds[].fields[].value    1024    char'
    'Footer         .footer.text                2048    char'
    'Total          na                          1000    char'
)

results=()

limitChecks() {

    local json="$1"

    local limitsIndex=0


    #jq '.embeds | to_entries | map(.key as $i | (.value.fields | length) as $c | range($c) | $i)'

    setCurrentObject "Content"

    count=$(jq "$field | length" <<< "${json}")

    updateResults ${count}

    echo "Content: ${count}"

    setCurrentObject "Embeds"

    embedsCount=$(jq "$field | length" <<< "${json}")

    updateResults ${embedsCount}

    echo "Embeds: ${embedsCount}"

    totalCharactersAllEmbeds=0

    # Check objects in each embed
    for (( i=0; i<$embedsCount; i++ )); do

        embed=$(jq -r ".embeds[$i]" <<< "${json}")

        totalCharactersPerEmbed=0

        # Check character limits
        for limit in "${limits[@]}"; do

            # Get current line values
            IFS=' ' read -r name field value type result <<< "$limit"

            # Check if limit is a 'character' limit
            if [[ "${field}" == *".embeds[]"* ]]; then

                element="${field//'.embeds[]'/}"

                if [ "${type}" == "char" ]; then

                    # Check if object is a field object as this is an array
                    if [[ "${field}" == *".fields[]"* ]]; then

                        # Remove parent object from element name
                        element="${element//'.fields[]'/}"

                        # Get the character count sum for each child element of the field object
                        count=$(jq ".fields | map($element | length) | add" <<< "${embed}")

                    else

                        count=$(jq "$element | length" <<< "${embed}")

                    fi

                    totalCharactersPerEmbed=$((totalCharactersPerEmbed + count))

                else

                    count=$(jq "$element | length" <<< "${embed}")

                fi

                updateResults ${count}

                echo " - ${name}: ${count}"

            fi

        done

        echo " - Total (pr. embed): ${totalCharactersPerEmbed}"

        totalCharactersAllEmbeds=$((totalCharactersAllEmbeds + totalCharactersPerEmbed))

    done

    echo "Total: ${totalCharactersAllEmbeds}"

    setCurrentObject "Footer"

    count=$(jq "$field | length" <<< "${json}")

    updateResults ${count}

    echo "Footer: ${count}"


    for r in "${results[@]}"; do
        echo "${r}"
    done


    # Check character limits
    for object in "${limits[@]}"; do

        # Get current line values
        IFS=' ' read -r name field limit type result <<< "$object"

            #jq -r "[$field | length]" <<< "${json}"

            # The field limit is pr. embed
            # for (( i=0; i<$embedsCount; i++ )); do

            #     embed=$(jq '.embeds[$i]' <<< "${json}")

            #     element="${field//'.embeds[]'/}"

            #     jq -r 'map($element | length | add)' <<< "${embed}"

            # done


        # Check number of embeds objects
        if [ "${name}" == "Embeds" ]; then

            embedsCount=$(jq "$field | length" <<< "${json}")

            check=$((embedsCount > limit ? 0 : 1))

            limits[$limitsIndex]+=" ${check}"

            echo "Embeds: ${embedsCount}"

        fi


        if  [ "${name}" == "Fields" ]; then

            fieldCount=0
            check=1

            # The field limit is pr. embed
            for (( index=0; index<$embedsCount; index++ )); do

                fieldCount=$(jq ".embeds[$index].fields | length" <<< "${json}")

                echo ${fieldCount}

                if [[ ${fieldCount} -gt ${limit} ]]; then

                    check=0

                fi

            done

            limits[$limitsIndex]+=" ${check}"

            echo Fields: ${fieldCount}

        fi



        # Check if limit is a 'character' limit
        if [ "${type}" == "char" ] && [ "${name}" != "Total" ]; then

            echo "${name}:"

            check=1

            while IFS=$'\t' read -r characters; do

                # Check character length against limit
                if [[ ${characters} -gt ${limit} ]]; then

                    echo -e "\033[33m${characters}\033[0m"
                    check=0

                else

                    echo "$characters"

                fi

                if [ "${name}" != "Content" ] && [ "${name}" != "Footer" ]; then

                    totalCharacters=$((totalCharacters + characters))
                fi

            done < <(jq -r "$field | length" <<< "${json}")

            limits[$limitsIndex]+=" ${check}"

        fi


        if [ "${name}" == "Total" ]; then

            echo Total Characters: ${totalCharacters}

            check=$((totalCharacters > limit ? 0 : 1))

            limits[$limitsIndex]+=" ${check}"

        fi

        (( limitsIndex++ ))

    done

    # for element in "${results[@]}"; do
    #     echo $(echo "${element}")
    # done

    for el in "${limits[@]}"; do
        echo $(echo "${el}")
    done

    criticalResult=false

    for objectLimitResult in "${limits[@]}"; do

        IFS=' ' read -r name field limit type result <<< "$objectLimitResult"

        if [ "${result}" != "1" ] && [ "${name}" != "Embeds" ] && [ "${name}" != "Total" ]; then

            criticalResult=true
            break

        fi

    done

    # Exit with failure of
    if ${criticalResult}; then

        echo "Content outside unmanageable limits. Unable to send webhook."

        exit 0

    # Check if embeds objects or total characters are outside limit
    elif outsideLimits "Embeds" || outsideLimits "Total"; then

        echo "Content outside manageable limits. Splitting webhook message"

        # Remove embeds object
        discordJsonMinusEmbeds=$(jq "del(.embeds)" <<< "${json}")

        # Send Discord Json data without embeds
        #sendWebhook "${discordJsonMinusEmbeds}" true

        # Send each embeds
        for (( index=0; index<$embedsCount; index++ )); do

            embed=$(jq ".embeds[$index]" <<< "${json}")
            discordJsonSingleEmbed=$(jq ".embeds=[$embed] | del(.content)" <<< "${json}")

            # Send single embed without the rest of the data
            #sendWebhook "${discordJsonSingleEmbed}" false

        done

    else

        echo "Content within limits. Sending full webhook message."

        # Send full Json
        #sendWebhook "${json}" false

    fi

}

setCurrentObject() {

    local objectName="$1"

    object=$(printf '%s\n' "${limits[@]}" | grep "${objectName}")

    IFS=' ' read -r name field value type result <<< "$object"

}

updateResults() {

    local result="$1"

    if [[ ${result} -gt ${value} ]]; then

        results+=("${name} ${field} ${value} ${type} ${result}")

    fi

}

# Return result of specific object limit check
outsideLimits() {

    local objectName="$1"

    # Return object limit result as success/failure
    return $(printf '%s\n' "${limits[@]}" | grep "${objectName}" | awk '{print $5}')

}



#### DISCORD VARIABLES ####

# Parsed from command line arguments.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--content)
            discordMessageContent="$2"
            shift 2
            ;;
        -e|--embeds)
            discordMessageEmbeds="$2"
            shift 2
            ;;
        -f|--file)
            discordAttachmentPath="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Invalid option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Discord webhook address base.
discordWebhookBase="https://discord.com/api/webhooks"

# Import secret variables.
source ${scriptPath}/discord-variables.sh

# Discord secret variables.
discordToken=${DISCORD_TOKEN}
discordID=${DISCORD_ID}
discordUsername=${DISCORD_USER}
discordAvatarURL=${DISCORD_AVATAR_URL}
discordRoleID=${DISCORD_ROLE_ID}

#### REPLACE ROLES ####

# Replace @admin mention with correct ID.
discordMessageEmbeds=$(echo "${discordMessageEmbeds}" | sed 's/\@admin/\<\@\&'${discordRoleID}'/g')


#### DISCORD NOTIFICATION ####

# Complete the Discord JSON string.
discordJson='{ "username":"'"${discordUsername}"'",
               "content":"'"${discordMessageContent}"'",
               "avatar_url":"'"${discordAvatarURL}"'",
               "allowed_mentions": {
                 "roles": [ "'"${discordRoleID}"'" ]
               },
               "embeds": [ '${discordMessageEmbeds%?}' ]
             }'



# Send Discord notification.
function sendWebhook() {

    local discordJsonData="$1"
    local includeAttatchment="$2"

    if [ -z "${discordAttachmentPath}" ] || [ "${includeAttatchment}" = "false" ]; then

        curl -H "Content-Type: application/json" -d "$discordJsonData" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    else

        curl -F payload_json="${discordJsonData}" -F "file1=@${discordAttachmentPath}" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    fi

}

limitChecks "${discordJson}"

#sendWebhook "${discordJson}" true