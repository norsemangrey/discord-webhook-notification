#!/bin/bash

jsonContent=$1

# Character lenght limits & object count limits
limits=(
    'Content        .content                    2000    char    1'
    'Embeds         .embeds                     10      obj     0'
    'Author         .embeds[].author.name       256     char    1'
    'Title          .embeds[].title             256     char    1'
    'Description    .embeds[].description       1024    char    1'
    'Fields         .embeds[].fields            25      obj     1'
    'Name           .embeds[].fields[].name     256     char    1'
    'Value          .embeds[].fields[].value    1024    char    1'
    'Footer         .footer.text                2048    char    1'
    'Totals         na                          6000    char    1'
    'Total          na                          6000    char    0'
)

headings="name field value type critical count"

criticalResult=false
outsideLimits=false

totalCharactersAllEmbeds=0


function updateResults() {

    echo "${name}: ${count}"

    if [[ ${count} -gt ${value} ]]; then

        outsideLimits=true

        if [ "${critical}" == "1" ]; then

            criticalResult=true

        fi

        results+="${name} ${field} ${value} ${type} ${critical} ${count}\n"

    fi

}


for limit in "${limits[@]}"; do

    IFS=' ' read -r $headings <<< "$limit"

    # Check if limit is a 'character' limit
    if [[ "${field}" == *".embeds[]"* ]]; then

        for (( i=0; i<$embedsCount; i++ )); do

            embed=$(jq -r ".embeds[$i]" <<< "${jsonContent}")

            element="${field//'.embeds[]'/}"

            # Check if object is a field object as this is an array
            if [[ "${field}" == *".fields[]"* ]]; then

                # Remove parent object from element name
                element="${element//'.fields[]'/}"

                # Get the character count sum for each child element of the field object
                count=$(jq ".fields | map($element | length) | add" <<< "${embed}")

            else

                count=$(jq "$element | length" <<< "${embed}")

            fi

            [ "${type}" == "char" ] && ((embedTotals[$i]+=count))

            updateResults

        done

    elif [[ "${name}" == "Totals" ]]; then

        for count in "${embedTotals[@]}"; do

            updateResults

            ((totalCharactersAllEmbeds+=count))

        done

    elif [[ "${name}" == "Total" ]]; then

        count=${totalCharactersAllEmbeds}

        updateResults

    else

        count=$(jq "$field | length" <<< "${jsonContent}")

        if [[ "${name}" == "Embeds" ]]; then

            embedsCount=${count}

            for (( i=0; i<$embedsCount; i++ )); do

                embedTotals[$i]=0

            done

        fi

        updateResults

    fi


done

results="${results%??}"

echo -e "${results}"

if ${criticalResult}; then
    exit 2
elif ${outsideLimits}; then
    exit 1
else
    exit 0
fi