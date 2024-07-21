#!/bin/bash

# Replace with your actual values
CLOUDFLARE_API_TOKEN="******"
CLOUDFLARE_ZONE_ID="*******"
DOMAIN="test.net"


# Fetch data
response=$(curl -s -X POST "https://nnr.moe/api/servers" -H "token: 5caa833c-9e81-4bc6-a85b-a122035406e3")

# Check if the response status is 1
status=$(echo $response | jq '.status')
if [ "$status" -ne 1 ]; then
    echo "Failed to fetch data"
    exit 1
fi

# Extract data
data=$(echo $response | jq -c '.data[]')

# Get existing DNS records
existing_records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" | jq -c '.result[]')

# List of records to keep 不删除的记录
keep_records=("www.$DOMAIN" "api1.$DOMAIN" "api2.$DOMAIN" "api3.$DOMAIN" "$DOMAIN")

# Iterate over existing records and delete those not present in the new data or with mismatched IPs, excluding keep_records
echo "$existing_records" | while read -r record; do
    record_name=$(echo $record | jq -r '.name')
    record_id=$(echo $record | jq -r '.id')
    record_content=$(echo $record | jq -r '.content')

    # Skip the records to keep
    if [[ " ${keep_records[@]} " =~ " ${record_name} " ]]; then
        continue
    fi

    sid=$(echo $record_name | sed -e "s/.$DOMAIN//")

    # Check if the sid exists in the new data
    server=$(echo "$data" | jq -c --arg sid "$sid" 'select(.sid == $sid)')
    if [ -z "$server" ]; then
        # SID not found in new data, delete the record
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json"
        echo "Deleted record: $record_name (SID not found)"
    else
        # SID found, check if the host contains the record content
        host=$(echo $server | jq -r '.host' | tr ',' '\n')
        if ! echo "$host" | grep -q "$record_content"; then
            # IP not found in the new host list, delete the record
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json"
            echo "Deleted record: $record_name (IP mismatch)"
        fi
    fi
done

# Iterate over the new data and create/update DNS records
echo "$data" | while read -r server; do
    sid=$(echo $server | jq -r '.sid')
    hosts=$(echo $server | jq -r '.host' | tr ',' '\n')
    name="$sid.$DOMAIN"

    echo "$hosts" | while read -r host; do
        if [[ "$host" == *:* ]]; then
            type="AAAA"
        else
            type="A"
        fi

        existing_record=$(echo "$existing_records" | jq -c --arg name "$name" --arg type "$type" 'select(.name == $name and .type == $type and .content == "'"$host"'")')

        if [ -n "$existing_record" ]; then
            record_id=$(echo $existing_record | jq -r '.id')
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$host\",\"ttl\":1,\"proxied\":false}"
            echo "Updated record: $name ($type) -> $host"
        else
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$host\",\"ttl\":1,\"proxied\":false}"
            echo "Created record: $name ($type) -> $host"
        fi
    done
done
