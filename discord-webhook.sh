#!/usr/bin/bash

#### SET PATHS ####

# Get path to where script is located.
scriptPath=$(echo "${0%/*}")

# Set other paths.
limitCheckScrip=${scriptPath}/discord-webhook-data-limit-check.sh
lastMessageFile=${scriptPath}/discord-webhook-last-message.json

#### SCRIP USAGE FUNCTION ####

# Usage function.
usage() {
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --content <content>   Set the content of the Discord message."
    echo "  -e, --embeds <embeds>     Set the embeds of the Discord message."
    echo "  -f, --file <file-path>    Set the file attachment path (optional)."
    echo "  -h, --help                Show this help message and exit."
    echo ""
    echo "Refer to the Discord documentation for more information on Webhooks"
    echo ""
    echo "  https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks"
    echo ""
}

### SEND WEBHOOK FUNCTION ###

# Send Discord notification with or without payloaad.
sendWebhook() {

    local discordJsonData="$1"
    local includeAttachment="$2"

    # Write last message that was attmepted to be sent to file
    echo "${discordJsonData}" > ${lastMessageFile}

    # Check if attachment pathe exits and if is should be included in the message
    if [ -z "${discordAttachmentPath}" ] || [ "${includeAttachment}" = "false" ]; then

        # Send message without attachment
        curl -H "Content-Type: application/json" -d "$discordJsonData" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    else

        # Send message with attachment
        curl -F payload_json="${discordJsonData}" -F "file1=@${discordAttachmentPath}" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

    fi

}

#### PARSE ARGUMENTS ####

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

#### DISCORD VARIABLES ####

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

#### BUILD DISCORD MESSAGE ####

# Complete the Discord JSON string.
discordJson='{ "username":"'"${discordUsername}"'",
               "content":"'"${discordMessageContent}"'",
               "avatar_url":"'"${discordAvatarURL}"'",
               "allowed_mentions": {
                 "roles": [ "'"${discordRoleID}"'" ]
               },
               "embeds": [ '${discordMessageEmbeds%?}' ]
             }'

#### MESSAGE LIMIT CHECK & SEND ####

# Call script to perform limit checks
${limitCheckScrip} -m "${discordJson}"

# Send full, split or drop message based in limit check
case ${?} in

    # Send full message
    0)
        echo "Content within limits. Sending full webhook message."

        # Send full Json
        sendWebhook "${discordJson}" true
        ;;

    # Split message in multiple webhooks
    1)
        echo "Content to large, but within manageable limits. Splitting webhook message"

        # Remove embeds section
        discordJsonMinusEmbeds=$(jq "del(.embeds)" <<< "${discordJson}")

        # Send message without embeds
        sendWebhook "${discordJsonMinusEmbeds}" true

        # Get number of embeds in original message
        embedsCount=$(jq ".embeds | length" <<< "${discordJson}")

        # Send each embed as a separate message
        for (( index=0; index<$embedsCount; index++ )); do

            # Get current embed in embeds section
            embed=$(jq ".embeds[$index]" <<< "${discordJson}")

            # Replace embeds in orignal message with current single embed and remove content section
            discordJsonSingleEmbed=$(jq ".embeds=[$embed] | del(.content)" <<< "${discordJson}")

            # Send message with single embed and without the rest of the data
            sendWebhook "${discordJsonSingleEmbed}" false

        done
        ;;

    # Drop message and exit with error
    *)
        echo "Error: Content outside manageable limits. Unable to send webhook." >&2
        exit 1
        ;;

esac