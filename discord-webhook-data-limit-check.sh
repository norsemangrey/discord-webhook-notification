#!/bin/bash

# Your JSON file path
json_file="./tmp2.json"

# Specify the field names you want to check
fields_to_check=("description" "value")
field_name="description"

lengthLimits=(
    'Content .content 2000'
    'Title .embeds[].title 256'
    'Description .embeds[].description 4096'
    'Author .embeds[].author.name 256'
    'Name .embeds[].fields[].name 256'
    'Value .embeds[].fields[].value 1024'
    'Footer .footer.text 2048'
)

countLimits=(
    'Embeds .embeds 10'
    'Fields .embeds[].fields 25'
)

results=()

IFS=' ' read -r name field limit <<< "${countLimits[0]}"

embedsCount=$(jq "$field | length" ${json_file})

#[ $embedsCount -gt $limit ] && ( check=0 ) || ( check=1 )
check=$((embedsCount > limit ? 0 : 1))

results+=("${name} ${check}")

echo "Embeds: ${embedsCount}"

IFS=' ' read -r name field limit <<< "${countLimits[1]}"

fieldCount=0
check=1

# The field limit is pr. embed
for (( index=1; index<=$embedsCount; index++ )); do

    fieldCount=$(jq --argjson index "$index" '.embeds[$index].fields | length' ${json_file})

    if [[ ${fieldCount} -gt ${limit} ]]; then

        check=0

    fi

done



results+=("${name} ${check}")

echo Fields: ${fieldCount}


for fieldLimit in "${lengthLimits[@]}"; do

    IFS=' ' read -r name field limit <<< "$fieldLimit"

    echo "${name}:"

    check=1

    while IFS=$'\t' read -r characters; do

        if [[ ${characters} -gt ${limit} ]]; then

            echo -e "\033[33m${characters}\033[0m"
            check=0

        else

            echo "$characters"

        fi

        if [[ "${name}" != "Content" ]]; then

            total=$((total + characters))
        fi

    done < <(jq -r "$field | length" ${json_file})

    results+=("${name} ${check}")

done

echo Total Characters: ${total}

check=$((total > 6000 ? 0 : 1))

results+=("Total ${check}")

for element in "${results[@]}"; do

    echo "$element"

done