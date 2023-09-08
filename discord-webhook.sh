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

discordMessageEmbeds=$(echo "${discordMessageEmbeds}" | sed 's/\@admin/<\@\&'${discordRoleID}'>/g')


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
if [[ -z "${discordAttachmentPath}" ]]; then

    curl -H "Content-Type: application/json" -d "$discordJson" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

else

    curl -F payload_json="${discordJson}" -F "file1=@${discordAttachmentPath}" ${discordWebhookBase}"/"${discordID}"/"${discordToken}

fi