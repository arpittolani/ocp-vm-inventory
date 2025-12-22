#!/bin/bash

# Define the comprehensive header
echo '"Namespace","VM_Name","Status","OS_Guest","Node","vCPUs","Memory_Request_Gi","Disk_1_Size_Gi","Disk_2_Size_Gi","Disk_3_Size_Gi","NIC_1_NAD","NIC_1_MAC","NIC_1_IP","NIC_2_NAD","NIC_2_MAC","NIC_2_IP","NIC_3_NAD","NIC_3_MAC","NIC_3_IP"'

# Helper function for size normalization
normalize_size_to_gib() {
    local SIZE_STR="$1"
    if [ -z "$SIZE_STR" ] || [ "$SIZE_STR" == "null" ]; then echo ""; return; fi
    echo "$SIZE_STR" | awk '{
        size=$1; unit=substr(size, length(size)-1);
        val=size; gsub(/[GgMmKkIiTt]/,"",val);
        if (unit ~ /Gi/) { printf "%.0f", val }
        else if (unit ~ /Ti/) { printf "%.0f", val * 1024 }
        else if (unit ~ /Mi/) { printf "%.2f", val / 1024 }
        else if (unit ~ /Ki/) { printf "%.3f", val / (1024*1024) }
        else { printf "%.0f", val / 1073741824 }
    }' 2>/dev/null
}

# Main Loop
oc get vm --all-namespaces -o json | jq -c '.items[]' | while read -r VM; do
    NAMESPACE=$(echo "$VM" | jq -r '.metadata.namespace')
    VM_NAME=$(echo "$VM" | jq -r '.metadata.name')
    VMI_EXISTS=$(echo "$VM" | jq -r '.status.ready // "false"')

    # Default values
    STATUS="Stopped"; OS_GUEST=""; NODE=""; VCPUS=""; MEMORY_REQUEST=""
    D1=""; D2=""; D3=""; N1_NAD=""; N1_MAC=""; N1_IP=""; N2_NAD=""; N2_MAC=""; N2_IP=""; N3_NAD=""; N3_MAC=""; N3_IP=""

    if [ "$VMI_EXISTS" == "true" ]; then
        STATUS="Running"
        VMI_JSON=$(oc get vmi "$VM_NAME" -n "$NAMESPACE" -o json 2>/dev/null)
        if [ $? -eq 0 ]; then
            OS_GUEST=$(echo "$VMI_JSON" | jq -r '.status.guestOSInfo.prettyName // "Unknown"')
            NODE=$(echo "$VMI_JSON" | jq -r '.status.nodeName // "N/A"')
            
            # Compute
            VCPUS=$(echo "$VMI_JSON" | jq -r '(.spec.domain.cpu.cores // 1) * (.spec.domain.cpu.sockets // 1)')
            MEMORY_REQUEST=$(normalize_size_to_gib "$(echo "$VMI_JSON" | jq -r '.spec.domain.resources.requests.memory // ""')")

            # Disks (extract up to 3)
            D_SIZES=$(echo "$VMI_JSON" | jq -r '.status.volumeStatus | .[].persistentVolumeClaimInfo.capacity.storage // .[].size // ""')
            D1=$(normalize_size_to_gib "$(echo "$D_SIZES" | sed -n '1p')")
            D2=$(normalize_size_to_gib "$(echo "$D_SIZES" | sed -n '2p')")
            D3=$(normalize_size_to_gib "$(echo "$D_SIZES" | sed -n '3p')")

            # NICs (extract up to 3)
            NIC_INFO=$(echo "$VMI_JSON" | jq -r '.status.interfaces[] as $si | .spec.networks[] as $sn | select($si.name == $sn.name) | [($sn.multus.networkName // $sn.name), $si.mac, $si.ipAddress] | join(",")')
            N1_NAD=$(echo "$NIC_INFO" | sed -n '1p' | cut -d',' -f1); N1_MAC=$(echo "$NIC_INFO" | sed -n '1p' | cut -d',' -f2); N1_IP=$(echo "$NIC_INFO" | sed -n '1p' | cut -d',' -f3)
            N2_NAD=$(echo "$NIC_INFO" | sed -n '2p' | cut -d',' -f1); N2_MAC=$(echo "$NIC_INFO" | sed -n '2p' | cut -d',' -f2); N2_IP=$(echo "$NIC_INFO" | sed -n '2p' | cut -d',' -f3)
            N3_NAD=$(echo "$NIC_INFO" | sed -n '3p' | cut -d',' -f1); N3_MAC=$(echo "$NIC_INFO" | sed -n '3p' | cut -d',' -f2); N3_IP=$(echo "$NIC_INFO" | sed -n '3p' | cut -d',' -f3)
        fi
    fi

    # Output quoted CSV row
    echo "\"$NAMESPACE\",\"$VM_NAME\",\"$STATUS\",\"$OS_GUEST\",\"$NODE\",\"$VCPUS\",\"$MEMORY_REQUEST\",\"$D1\",\"$D2\",\"$D3\",\"$N1_NAD\",\"$N1_MAC\",\"$N1_IP\",\"$N2_NAD\",\"$N2_MAC\",\"$N2_IP\",\"$N3_NAD\",\"$N3_MAC\",\"$N3_IP\""
done
