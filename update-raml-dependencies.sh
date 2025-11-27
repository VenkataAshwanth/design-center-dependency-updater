#!/bin/bash

getAllProjects() {
    #Fetch all the projects available in the organization using provided ORG_ID
    PROJECTS="[]"
    PAGE_INDEX=0

    while :; do
        # Fetch projects for the current page
        RESPONSE=$(curl -s -X GET "https://anypoint.mulesoft.com/designcenter/api/v2/organizations/$ORG_ID/projects?pageSize=100&pageIndex=$PAGE_INDEX&orderBy=-updateDate" \
            -H "Authorization: Bearer $ACCESS_TOKEN")

        # Check for API errors
        if [ $? -ne 0 ] || [ -z "$RESPONSE" ] || [ "$RESPONSE" == "null" ]; then
            echo -e "❌ \033[1;31mFailed to fetch projects from page $PAGE_INDEX. Exiting.\033[0m"
            exit 1
        fi

        # Check if response is empty (end of pagination)
        PAGE_PROJECTS=$(echo "$RESPONSE" | jq '.')
        if [ "$(echo "$PAGE_PROJECTS" | jq 'length')" -eq 0 ]; then
            break
        fi

        # Append current page to accumulated projects
        PROJECTS=$(echo "$PROJECTS $PAGE_PROJECTS" | jq -s 'add')

        # Go to the next page
        ((PAGE_INDEX++))
    done
}

lockFunction() {
    # Acquire Lock
    echo -e "🔐 \033[1;34mAcquiring lock for $PROJECT_NAME...\033[0m"
    LOCK_RESPONSE=$(curl -s -X POST "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/acquireLock" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "x-organization-id: $ORG_ID" \
        -H "x-owner-id: $OWNER_ID" -d '{}')
    if [ $(echo "$LOCK_RESPONSE" | jq -r .locked) != "true" ]; then
        echo -e "❌ \033[1;31mFailed to acquire lock for $PROJECT_NAME. Skipping.\033[0m"
        exit 1
    fi
    echo -e "✅ \033[1;32mLock acquired successfully.\033[0m"

}

releaseLock() {
    # Release Lock
    echo -e "🔓 \033[1;34mReleasing lock for $PROJECT_NAME...\033[0m"
    RELEASE_RESPONSE=$(curl -s -X POST "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/releaseLock" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "x-organization-id: $ORG_ID" \
        -H "x-owner-id: $OWNER_ID" -d '{}')
    if [ $(echo "$RELEASE_RESPONSE" | jq -r .locked) != "false" ]; then
        echo -e "❌ \033[1;31mFailed to release lock for $PROJECT_NAME. Skipping.\033[0m"
        continue
    fi
    echo -e "✅ \033[1;32mLock released successfully.\033[0m"
}

getOwnerId() {
    #Fetch the owner Id of the connected app for current org
    echo -e "🔐 \033[1;34mFetching Owner ID of the connected app\033[0m"
    OWNER_ID_RESP=$(curl -s -X GET "https://anypoint.mulesoft.com/accounts/api/me" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    OWNER_ID=$(echo "$OWNER_ID_RESP" | jq -r .user.id)
    if [ -z "$OWNER_ID" ] || [ "$OWNER_ID" == "null" ]; then
        echo -e "❌ \033[1;31mFailed to get Owner ID. Skipping.\033[0m"
        exit 1
    fi
    echo -e "✅ \033[1;32mOwner ID - $OWNER_ID fetched successfully.\033[0m"
}

# Check if 'jq' is installed
if ! command -v jq &>/dev/null; then
    echo -e "❌ \033[1;31mError: 'jq' is not installed. Please install it and try again.\033[0m"
    exit 1
fi

# Validate yq installation
if ! command -v yq &>/dev/null; then
    echo "Error: 'yq' is not installed. Please install it and try again."
    exit 1
fi

# Input file containing org_id and project dependencies
INPUT_FILE=$1

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 Missing file <input.yaml>"
    exit 1
fi

# Reading input files and calculating the number of organizations
ORG_COUNT=$(yq eval '.organizations | length' "$INPUT_FILE")

#Printing the number of organizations
echo -e "\033[1;36m*************************************************************"
echo -e "📒 \033[1;36mNumber of organizations to process:  \033[1;36m$ORG_COUNT"
echo -e "\033[1;36m*************************************************************"

#Processing organizations one by one
for ((ORG_INDEX = 0; ORG_INDEX < ORG_COUNT; ORG_INDEX++)); do

    #Extracting ORG_ID, CLIENT_ID, CLIENT_SECRET for current organization
    ORG_ID=$(yq eval ".organizations[$ORG_INDEX].org_id" "$INPUT_FILE")
    CLIENT_ID=$(yq eval ".organizations[$ORG_INDEX].client_id" "$INPUT_FILE")
    CLIENT_SECRET=$(yq eval ".organizations[$ORG_INDEX].client_secret" "$INPUT_FILE")

    echo -e "\033[1;38;5;92m#####################################################################"
    echo -e "🚀 \033[1;38;5;92mProcessing Organization:\033[1;38;5;92m $ORG_ID"
    echo -e "\033[1;38;5;92m#####################################################################"
    # Export credentials for current organization
    export CLIENT_ID
    export CLIENT_SECRET

    CLIENT_ID=${CLIENT_ID:-""}
    CLIENT_SECRET=${CLIENT_SECRET:-""}

    # Prompt for Client ID and Client Secret for current organization if not provided as environment variables
    if [ -z "$CLIENT_ID" ]; then
        read -srp "Enter Client ID for $ORG_ID: " CLIENT_ID
    fi

    if [ -z "$CLIENT_SECRET" ]; then
        read -srp "Enter Client Secret $ORG_ID: " CLIENT_SECRET
    fi

    # Get Access Token for current org
    echo -e "🔑 \033[1;34mFetching access token for $ORG_ID...\033[0m"
    ACCESS_TOKEN=$(curl -s -X POST https://anypoint.mulesoft.com/accounts/api/v2/oauth2/token \
        -H "Content-Type: application/json" \
        -d '{"client_id":"'$CLIENT_ID'","client_secret":"'$CLIENT_SECRET'","grant_type":"client_credentials"}' | jq -r .access_token)

    if [ $? -ne 0 ] || [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
        echo -e "❌ \033[1;31mFailed to fetch access token. Exiting.\033[0m"
        exit 1
    fi

    echo -e "✅ \033[1;32mAccess token fetched successfully.\033[0m"

    # Get Project Names from the input file for current organization

    # Initialize an empty array
    PROJECT_NAMES=()

    # Extract project names and append them directly into the array
    while IFS= read -r PROJECT; do
        PROJECT_NAMES+=("\"$PROJECT\"")
    done < <(yq e ".organizations[$ORG_INDEX].projects[] | keys | .[]" "$INPUT_FILE")

    # Verify the array content
    echo "Extracted project names: ${PROJECT_NAMES[*]}"

    #Get all projects for current organization
    getAllProjects

    if [ $? -ne 0 ] || [ -z "$PROJECTS" ] || [ "$PROJECTS" == "null" ]; then
        echo -e "❌ \033[1;31mNo projects found for organization ID $ORG_ID. Exiting.\033[0m"
        exit 1
    fi

    #Get the owner Id for the provided connected app credentials
    getOwnerId

    # Get Project IDs for mentioned projects under current organization
    echo -e "📦 \033[1;34mFetching project IDs...\033[0m"
    PROJECT_IDS=()

    #Processing projects under current organization one by one
    for PROJECT_NAME in "${PROJECT_NAMES[@]}"; do

        # Remove surrounding quotes
        PROJECT_NAME=${PROJECT_NAME//\"/}

        echo -e "\033[1;38;5;130m-------------------------------------------------------------------\033[0m"
        echo -e "⏳ \033[1;38;5;130mProcessing project: $PROJECT_NAME\033[0m"
        echo -e "\033[1;38;5;130m-------------------------------------------------------------------\033[0m"

        PROJECT_ID=$(echo "$PROJECTS" | jq -r ".[] | select(.name==\"$PROJECT_NAME\") | .id")
        if [ -n "$PROJECT_ID" ]; then
            PROJECT_IDS+=($PROJECT_ID)
            echo -e "✅ \033[1;32mFound project ID for $PROJECT_NAME: $PROJECT_ID\033[0m"
        else
            echo -e "⚠️ \033[1;33mProject $PROJECT_NAME not found. Continuing to the next project.\033[0m"
            continue
        fi

        # Fetch 'defaultBranch' Fields
        echo -e "📂 \033[1;34mFetching project details for $PROJECT_NAME ($PROJECT_ID)...\033[0m"
        RESPONSE=$(curl -s -X GET "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "x-organization-id: $ORG_ID")

        DEFAULT_BRANCH=$(echo "$RESPONSE" | jq -r .defaultBranch)

        if [ -z "$DEFAULT_BRANCH" ] || [ "$DEFAULT_BRANCH" == "null" ]; then
            echo -e "❌ \033[1;31mFailed to fetch 'defaultBranch' for project ID $PROJECT_ID. Skipping.\033[0m"
            exit 1
        fi

        #Acquire lock to fetch the dependencies
        lockFunction

        #Fetch Dependencies (current existing dependencies)
        echo -e "\n📦 \033[1;34mFetching current dependencies for project ID $PROJECT_ID...\033[0m"
        EXCHANGE_JSON=$(curl -s -X PATCH "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/exchange/dependencies" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "x-organization-id: $ORG_ID" \
            -H "x-owner-id: $OWNER_ID")

        #echo $EXCHANGE_JSON

        releaseLock

        #Extracting the dependencies from the exchange.json
        CURRENT_DEPENDENCIES=$(echo "$EXCHANGE_JSON" | jq -c '.dependencies[] | {groupId, assetId, version}')
        echo -e "🔍 \033[1;34mDependencies found in project:\033[0m $(echo "$CURRENT_DEPENDENCIES" | jq .)"

        echo -e "🔄 \033[1;34mUpdating dependencies for $PROJECT_NAME ($PROJECT_ID) :\033[1;34m "

        # Prepare payload
        ADD_PAYLOAD='{"add": []}'
        REMOVE_PAYLOAD='{"remove": []}'

        #Extracting the dependencies
        INPUT_DEPENDENCIES=$(yq e ".organizations[$ORG_INDEX].projects[] | with_entries(select(.key == \"$PROJECT_NAME\")) | .[].[]" "$INPUT_FILE")

        echo -e "➡️  \033[1;38;5;92mDependencies to be updated for the project \033 $PROJECT_NAME\n$INPUT_DEPENDENCIES"

        #Filter only the dependencies from project matching the dependencies provided in input for the current project
        FILTERED_DEPENDENCIES='[]'

        for DEP in $INPUT_DEPENDENCIES; do

            FILTERED_DEP=$(echo "$CURRENT_DEPENDENCIES" | jq -c --arg ASSET_ID "$DEP" 'select(.assetId == $ASSET_ID)')

            #echo $FILTERED_DEP

            # If dependency is empty, print a warning and continue
            if [ -z "$FILTERED_DEP" ]; then
                echo -e "\033[1;33m⚠️ Warning: Dependency '$DEP' not found in exchange.json. Skipping...\033[0m"
                continue
            fi

            # Append the valid dependency to the JSON array
            FILTERED_DEPENDENCIES=$(echo "$FILTERED_DEPENDENCIES" | jq --argjson FIL_DEP "$FILTERED_DEP" '. += [$FIL_DEP]')

        done

        #echo "Filtered dependencies $FILTERED_DEPENDENCIES"
        DEPENDENCIES=$(echo "$FILTERED_DEPENDENCIES" | jq -c '.[]')
        #echo $DEPENDENCIES

        # Process each dependency one by one
        for DEPENDENCY in $DEPENDENCIES; do

            #Extract the Asset Id of the dependency
            ASSET_ID=$(echo "$DEPENDENCY" | jq -r .assetId)
            #echo $ASSET_ID

            #Extract the Current version of the dependency
            CURRENT_VERSION=$(echo "$DEPENDENCY" | jq -r .version)

            echo -e "\n🌐 \033[1;34mFetching details for dependency with Asset ID: '$ASSET_ID'...\033[0m"

            #Fetch the latest version of the dependencies by searching with the Asset Id
            ASSET_RESPONSE=$(curl -s -X GET "https://anypoint.mulesoft.com/exchange/api/v1/assets?search=$ASSET_ID" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "Content-Type: application/json")

            if [ $? -ne 0 ] || [ -z "$ASSET_RESPONSE" ] || [ "$ASSET_RESPONSE" == "null" ]; then
                echo -e "❌ Failed to fetch asset details for Asset ID: '$ASSET_ID'."
                continue
            fi

            #Filter out the Asset details from the Asset Response with Asset Id
            FILTERED_ASSET=$(echo "$ASSET_RESPONSE" | jq -c ".[] | select(.assetId==\"$ASSET_ID\")")
            if [ -z "$FILTERED_ASSET" ]; then
                echo -e "❌ No matching asset found for Asset ID: '$ASSET_ID'."
                continue
            fi

            #Extract the Group Id from the Asset details
            GROUP_ID=$(echo "$FILTERED_ASSET" | jq -r .groupId)
            #Extract the New version from the Asset details
            NEW_VERSION=$(echo "$FILTERED_ASSET" | jq -r .version)

            # Compare Current version and New version of dependencies
            if [ "$CURRENT_VERSION" == "$NEW_VERSION" ]; then
                # Since Current version and New version are same. No need to update dependency version. Skipping to the next one.
                echo -e "\033[1;35m👍 Dependency $ASSET_ID already up to date! Skipping...\033[0m"
                continue
            else
                # Since Current version and New version are different, proceeding further to next steps.
                echo -e "🔄 \033[1;36m Updating the Dependency $ASSET_ID\033[0m"
                echo -e "✅ \033[1;32mDependency Details -> Group ID: '$GROUP_ID', Asset ID: '$ASSET_ID', Version: '$NEW_VERSION'\033[0m"

                # Append to dynamic add payload
                ADD_PAYLOAD=$(echo "$ADD_PAYLOAD" | jq ".add += [{\"groupId\": \"$GROUP_ID\", \"assetId\": \"$ASSET_ID\", \"version\": \"$NEW_VERSION\"}]")
                #REMOVE_PAYLOAD=$(echo "$REMOVE_PAYLOAD" | jq ".remove += [$DEPENDENCY]")

                # Get all files
                FILES_LIST=$(curl -s -X GET "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/files" \
                    -H "Authorization: Bearer $ACCESS_TOKEN" \
                    -H "x-organization-id: $ORG_ID" \
                    -H "x-owner-id: $OWNER_ID" -d '{}')

                #Filter the files which has the dependency versions to be updated
                FILES_LIST=($(echo "$FILES_LIST" | jq -r '[.[] | select((.path | startswith("exchange") | not) and (.path != ".gitignore") and (.path != "exchange.json") and (.type != "FOLDER") and (.path | endswith(".json") | not) ) | .path] | .[]'))
                echo -e "$FILES_LIST"

                #Filename Patterns
                OLD_PATTERN="$GROUP_ID\/$ASSET_ID\/[0-9]+\.[0-9]+\.[0-9]+" # Escaped forward slashes
                NEW_PATTERN="$GROUP_ID/$ASSET_ID/$NEW_VERSION"
                NEW_PATTERN=$(echo "$NEW_PATTERN" | sed 's/\//\\\//g; s/\./\\./g')

                #echo -e "$OLD_PATTERN"
                #echo -e "$NEW_PATTERN"

                #Updating file content with new version for the dependency
                UPDATED_FILE_CONTENT_BODY='[]'
                for FILE in "${FILES_LIST[@]}"; do # Iterate over the array

                    FILE_PARAM=$(echo "$FILE" | sed 's/\//%2F/g')

                    echo "Filename : $FILE"
                    #Store file content
                    FILE_CONTENT=$(curl -s -X GET "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/files/$FILE_PARAM" \
                        -H "Authorization: Bearer $ACCESS_TOKEN" \
                        -H "x-organization-id: $ORG_ID" \
                        -H "x-owner-id: $OWNER_ID" -d '{}')

                    #echo "File content: $FILE_CONTENT"

                    if [ $? -eq 0 ] || [ -n "$FILE_CONTENT" ]; then

                        #echo 'SED PATTERN   s/'"$OLD_PATTERN"'/'"$NEW_PATTERN"'/g'

                        FILE_CONTENT=$(echo "$FILE_CONTENT" | sed -E 's/'"$OLD_PATTERN"'/'"$NEW_PATTERN"'/g')

                        #echo "Replaced FILE_CONTENT $FILE_CONTENT"

                        UPDATED_FILE_CONTENT_BODY=$(echo "$UPDATED_FILE_CONTENT_BODY" | jq --arg file "$FILE" --argjson content "$FILE_CONTENT" '. += [{"path":$file,"type":"FILE","content":$content}]')
                        #echo "Updated File content $UPDATED_FILE_CONTENT_BODY"

                        continue
                    fi
                done

            fi

            lockFunction

            RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/save" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "x-organization-id: $ORG_ID" \
                -H "x-owner-id: $OWNER_ID" \
                -H "Content-Type: application/json" \
                -d "$UPDATED_FILE_CONTENT_BODY")

            echo "Status - File save - $RESPONSE"

        done
        # echo -e "📦 \033[1;34mFinal Add Payload:\033[0m $(echo "$ADD_PAYLOAD" | jq .)"
        # echo -e "📦 \033[1;34mFinal Remove Payload:\033[0m $(echo "$REMOVE_PAYLOAD" | jq .)"

        #Merge remove and add payloads
        MERGED_PAYLOAD=$(echo "$ADD_PAYLOAD $REMOVE_PAYLOAD" | jq -s '.[0] * .[1]')
        if [ $? -ne 0 ] || [ -z "$MERGED_PAYLOAD" ]; then
            echo -e "❌ Failed to merge payloads for project ID $PROJECT_ID. Skipping."
            continue
        fi
        echo -e "🔗 \033[1;34mUpdate Dependencies Payload:\033[0m $(echo "$MERGED_PAYLOAD" | jq .)"

        # Check if both "add" and "remove" are empty arrays under MERGED_PAYLOAD
        if echo "$MERGED_PAYLOAD" | jq -e '.add == [] and .remove == []' >/dev/null; then
            echo -e "\033[1;35m👍 No dependencies to be updated in exchange.json. Skipping...\033[0m"
        else
            # Update Dependencies
            echo -e "🛠️ \033[1;34mUpdating dependencies for $PROJECT_NAME...\033[0m"
            # echo -e "\n🚀 \033[1;34mPosting merged payload to Design Center...\033[0m"
            RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://anypoint.mulesoft.com/designcenter/api-designer/projects/$PROJECT_ID/branches/$DEFAULT_BRANCH/exchange/dependencies" \
                -H "Authorization: Bearer $ACCESS_TOKEN" \
                -H "x-organization-id: $ORG_ID" \
                -H "x-owner-id: $OWNER_ID" \
                -H "Content-Type: application/json" \
                -d "$MERGED_PAYLOAD")

            if [ "$RESPONSE" -eq 200 ]; then
                echo -e "✅ \033[1;32mSuccessfully updated dependencies for project ID $PROJECT_ID.\033[0m"
            else
                echo -e "❌ \033[1;31mFailed to update dependencies for project ID $PROJECT_ID. HTTP Status Code: $RESPONSE\033[0m"
            fi

            releaseLock
        fi

        echo -e "✅ \033[1;32mProcessed project: $PROJECT_NAME ($PROJECT_ID) successfully.\033[0m"

    done

done
echo -e "🎉 \033[1;32m Execution completed.\033[0m"
