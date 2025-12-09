# OCP Virtualization Inventory Report (RVTools Equivalent)

This script generates a comprehensive, fixed-column inventory report for **Virtual Machines (VMs)** running on **OpenShift Virtualization (KubeVirt)** across all namespaces in the cluster. It aggregates data from `VirtualMachine` (`vm`) and `VirtualMachineInstance` (`vmi`) resources to provide a detailed, single-row summary for each VM, mimicking the format of tools like VMware's RVTools.

## Features & Focus

| Category | Details Extracted |
| :--- | :--- |
| **Compute** | vCPUs (Cores \* Sockets), Guaranteed Memory Request (GiB) |
| **Networking** | NAD Name, MAC, and IP Address for the first three (3) NICs. |
| **Storage** | Size in GiB for the first three (3) Disks (from PVC capacity). |
| **Core Info** | VM Name, Status (Running/Stopped), Host Node, and Guest OS Name. |

---

## Prerequisites

To run this script successfully, you must have the following installed and configured:

1.  **OpenShift CLI (`oc`)**: Must be logged in with cluster-wide read access (e.g., `cluster-admin` or a role with read access to all namespaces).
2.  **`jq`**: A command-line JSON processor.
3.  **`column`**: A utility for formatting output into neatly aligned columns (usually part of the `util-linux` package).

---

## How to Run

1.  **Save the Script**: Save the Bash code (the large script with all the functions) as a file named `ocp-rvtools.sh`.
2.  **Make Executable**:
    ```bash
    chmod +x ocp-rvtools.sh
    ```
3.  **Execute & View**: Run the script from your terminal. The output will be displayed directly, formatted in neat columns.
    ```bash
    ./ocp-rvtools.sh
    ```
4.  **Save to CSV**: To save the output as a clean CSV file (without the terminal formatting from `column -t`), redirect the output:
    ```bash
    ./ocp-rvtools.sh | tr -s '[:blank:]' ',' > vm_inventory_report.csv
    ```
    *(Note: Using `tr` here is a robust way to strip the `column -t` padding and ensure clean CSV output.)*

---

## Report Columns

The report provides a single row for each Virtual Machine, combining all compute, storage, and network metrics into a wide, fixed-column format. Empty columns mean the resource does not exist or the VM is stopped.

| Column Name |  Description |
| :--- |  :--- |
| **Namespace** | The project the VM belongs to. |
| **VM\_Name** | The name of the Virtual Machine. |
| **Status** | `Running` (if VMI exists) or `Stopped` (if VMI does not exist). |
| **OS\_Guest** | The guest operating system name (requires QEMU Guest Agent). |
| **Node** | The worker node the VM is currently running on. |
| **vCPUs** | Total calculated vCPUs (`cores` \* `sockets`). |
| **Memory\_Request\_Gi** | Guaranteed memory reservation (normalized to GiB). |
| **Disk\_1/2/3\_Size\_Gi** | Size of the first, second, and third persistent volumes (normalized to GiB). |
| **NIC\_1/2/3\_NAD** | The **Network Attachment Definition (NAD)** name for the NIC. |
| **NIC\_1/2/3\_MAC** | The assigned MAC address for the NIC.
