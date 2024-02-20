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

    # Check if attachment pathe exits and if is should be included in the message
    if [ -z "${discordAttachmentPath}" ] || [ "${includeAttatchment}" = "false" ]; then

        # Send message without attachment
        curl -H "Content-Type: application/json" -d "$discordJsonData" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    else

        # Send message with attachment
        curl -F payload_json="${discordJsonData}" -F "file1=@${discordAttachmentPath}" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    fi

}

# Call script to perform limit checks
${scriptPath}/discord-webhook-data-limit-check.sh "${discordJson}"

# Get results
limitCheckResult=$?

# Exit with failure of
if [[ ${limitCheckResult} -eq 2 ]]; then

    echo "Content outside manageable limits. Unable to send webhook."

# Check if embeds objects or total characters are outside limit
elif [[ ${limitCheckResult} -eq 1 ]]; then

    echo "Content to large, but within manageable limits. Splitting webhook message"

    # Remove embeds object
    discordJsonMinusEmbeds=$(jq "del(.embeds)" <<< "${discordJson}")

    # Send Discord Json data without embeds
    #sendWebhook "${discordJsonMinusEmbeds}" true

    embedsCount=$(jq ".embeds | length" <<< "${discordJson}")

    # Send each embeds
    for (( index=0; index<$embedsCount; index++ )); do

        embed=$(jq ".embeds[$index]" <<< "${discordJson}")
        discordJsonSingleEmbed=$(jq ".embeds=[$embed] | del(.content)" <<< "${discordJson}")

        # Send single embed without the rest of the data
        #sendWebhook "${discordJsonSingleEmbed}" false

    done

else

    echo "Content within limits. Sending full webhook message."

    # Send full Json
    #sendWebhook "${json}" false

fi

#sendWebhook "${discordJson}" true