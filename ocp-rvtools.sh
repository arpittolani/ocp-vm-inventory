#!/bin/bash

# A temporary file to hold the raw CSV data before formatting
TMP_CSV_FILE=$(mktemp)

# Define the comprehensive header for the fixed-column output (20 columns)
echo "Namespace,VM_Name,Status,OS_Guest,Node,vCPUs,Memory_Request_Gi,Disk_1_Size_Gi,Disk_2_Size_Gi,Disk_3_Size_Gi,NIC_1_NAD,NIC_1_MAC,NIC_1_IP,NIC_2_NAD,NIC_2_MAC,NIC_2_IP,NIC_3_NAD,NIC_3_MAC,NIC_3_IP" > "$TMP_CSV_FILE"

# Function to safely extract disk size from volumeStatus and normalize units to GiB
# This function is used for both storage and memory normalization.
normalize_size_to_gib() {
    local SIZE_STR="$1"

    # Handle empty or invalid input
    if [ -z "$SIZE_STR" ] || [ "$SIZE_STR" == "null" ]; then
        echo ""
        return
    fi

    # Use awk to convert sizes (like 200Gi, 512Mi) to GiB
    echo "$SIZE_STR" | awk '{
        size=$1; unit=substr(size, length(size)-1);
        val=size; gsub(/[GgMmKkIiTt]/,"",val);

        if (unit ~ /Gi/) { gsub(/Gi/,"",size); printf "%.0f", size }
        else if (unit ~ /Ti/) { gsub(/Ti/,"",size); printf "%.0f", val * 1024 }
        else if (unit ~ /Mi/) { gsub(/Mi/,"",size); printf "%.2f", val / 1024 }
        else if (unit ~ /Ki/) { gsub(/Ki/,"",size); printf "%.3f", val / (1024*1024) }
        else if (unit ~ /G/) { gsub(/G/,"",size); printf "%.0f", size }
        else if (unit ~ /M/) { gsub(/M/,"",size); printf "%.2f", val / 1024 }
        else if (unit ~ /K/) { gsub(/K/,"",size); printf "%.3f", val / (1024*1024) }
        else { printf "%.0f", size / 1073741824 }
    }' 2>/dev/null
}

# Function to safely extract the size of a specific disk from VMI status
extract_disk_size() {
    local VMI_JSON="$1"
    local DISK_INDEX="$2"

    # Extract all volume sizes, preferring PVC capacity (for persistent disks) or size (for others like cloudinit)
    local SIZE_STRINGS=$(echo "$VMI_JSON" | jq -r '
        .status.volumeStatus | .[].persistentVolumeClaimInfo.capacity.storage //
        .[].size // "0"
    ' 2>/dev/null)

    # Get the specific size string for the requested index (1-based)
    local RAW_SIZE=$(echo "$SIZE_STRINGS" | sed -n "${DISK_INDEX}p")

    # Normalize and return the size in GiB
    normalize_size_to_gib "$RAW_SIZE"
}

# Function to safely extract NIC details (NAD, MAC, or IP)
extract_nic_details() {
    local VMI_JSON="$1"
    local NIC_INDEX="$2" # 1-based index
    local DETAIL_TYPE="$3" # NAD, MAC, IP

    # The NIC_INDEX needs to be translated to a 0-based index for jq: .[NIC_INDEX - 1]
    local JQ_INDEX=$((NIC_INDEX - 1))

    # Use jq to join data from status.interfaces (MAC/IP) and spec.networks (NAD Name)
    NIC_INFO=$(echo "$VMI_JSON" | jq -r '
        .status.interfaces[] as $si |
        .spec.networks[] as $sn |
        # Match by the internal name
        select($si.name == $sn.name) |
        # Create an array of details for all NICs
        [ ($sn.multus.networkName // $sn.name), ($si.mac // ""), ($si.ipAddress // "") ] |
        # Flatten the array of arrays and join into a string for easier parsing
        join(",")
    ' 2>/dev/null)

    # Convert the multi-line, comma-separated NIC info into a bash array for indexing
    IFS=$'\n' read -r -a NIC_ARRAY <<< "$NIC_INFO"

    # Check if the requested NIC index exists
    if [ ${#NIC_ARRAY[@]} -ge "$NIC_INDEX" ]; then
        # Extract the specific NIC entry (e.g., "default/snx-vlan-60,02:c3:da:00:00:08,139.10.96.234")
        NIC_ENTRY=${NIC_ARRAY[JQ_INDEX]}

        # Determine which detail to return (1=NAD, 2=MAC, 3=IP)
        if [ "$DETAIL_TYPE" == "NAD" ]; then
            echo "$NIC_ENTRY" | cut -d',' -f1
        elif [ "$DETAIL_TYPE" == "MAC" ]; then
            echo "$NIC_ENTRY" | cut -d',' -f2
        elif [ "$DETAIL_TYPE" == "IP" ]; then
            echo "$NIC_ENTRY" | cut -d',' -f3
        fi
    fi
}


# --- Main Logic ---

# Get a list of all VirtualMachines (VMs) across all namespaces
oc get vm --all-namespaces -o json | jq -c '.items[]' | while read -r VM; do
    NAMESPACE=$(echo "$VM" | jq -r '.metadata.namespace')
    VM_NAME=$(echo "$VM" | jq -r '.metadata.name')
    VMI_EXISTS=$(echo "$VM" | jq -r '.status.ready // "false"')

    # Initialize all dynamic columns to empty
    VCPUS=""
    MEMORY_REQUEST=""
    DISK_1_SIZE=""
    DISK_2_SIZE=""
    DISK_3_SIZE=""
    NIC_1_NAD=""
    NIC_1_MAC=""
    NIC_1_IP=""
    NIC_2_NAD=""
    NIC_2_MAC=""
    NIC_2_IP=""
    NIC_3_NAD=""
    NIC_3_MAC=""
    NIC_3_IP=""

    STATUS="Stopped"
    OS_GUEST=""
    NODE=""

    # 1. Process Running VMs
    if [ "$VMI_EXISTS" == "true" ]; then
        STATUS="Running"
        VMI_JSON=$(oc get vmi "$VM_NAME" -n "$NAMESPACE" -o json 2>/dev/null)

        if [ $? -eq 0 ]; then
            OS_GUEST=$(echo "$VMI_JSON" | jq -r '.status.guestOSInfo.prettyName // "Unknown (No Guest Agent)"')
            NODE=$(echo "$VMI_JSON" | jq -r '.status.nodeName // "N/A"')

            # --- Compute Information ---
            CORES=$(echo "$VMI_JSON" | jq -r '.spec.domain.cpu.cores // 0')
            SOCKETS=$(echo "$VMI_JSON" | jq -r '.spec.domain.cpu.sockets // 0')
            # Calculate total vCPUs
            VCPUS=$((CORES * SOCKETS))

            # Extract and normalize Memory Request
            RAW_MEMORY_REQUEST=$(echo "$VMI_JSON" | jq -r '.spec.domain.resources.requests.memory // ""')
            MEMORY_REQUEST=$(normalize_size_to_gib "$RAW_MEMORY_REQUEST")


            # --- Storage Information (up to 3 disks) ---
            DISK_1_SIZE=$(extract_disk_size "$VMI_JSON" 1)
            DISK_2_SIZE=$(extract_disk_size "$VMI_JSON" 2)
            DISK_3_SIZE=$(extract_disk_size "$VMI_JSON" 3)

            # --- NIC Information (up to 3 NICs) ---
            NIC_1_NAD=$(extract_nic_details "$VMI_JSON" 1 "NAD")
            NIC_1_MAC=$(extract_nic_details "$VMI_JSON" 1 "MAC")
            NIC_1_IP=$(extract_nic_details "$VMI_JSON" 1 "IP")

            NIC_2_NAD=$(extract_nic_details "$VMI_JSON" 2 "NAD")
            NIC_2_MAC=$(extract_nic_details "$VMI_JSON" 2 "MAC")
            NIC_2_IP=$(extract_nic_details "$VMI_JSON" 2 "IP")

            NIC_3_NAD=$(extract_nic_details "$VMI_JSON" 3 "NAD")
            NIC_3_MAC=$(extract_nic_details "$VMI_JSON" 3 "MAC")
            NIC_3_IP=$(extract_nic_details "$VMI_JSON" 3 "IP")
        fi
    fi

    # 2. Output the single fixed row
    echo "$NAMESPACE,$VM_NAME,$STATUS,$OS_GUEST,$NODE,$VCPUS,$MEMORY_REQUEST,$DISK_1_SIZE,$DISK_2_SIZE,$DISK_3_SIZE,$NIC_1_NAD,$NIC_1_MAC,$NIC_1_IP,$NIC_2_NAD,$NIC_2_MAC,$NIC_2_IP,$NIC_3_NAD,$NIC_3_MAC,$NIC_3_IP" >> "$TMP_CSV_FILE"

done

# --- FINAL STEP: Apply 'column -t' to the full file for perfect alignment ---
cat "$TMP_CSV_FILE" | column -t -s','

# Clean up the temporary file
rm "$TMP_CSV_FILE"
