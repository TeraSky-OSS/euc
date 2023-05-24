<#
.SYNOPSIS
    This script performs the VM cloning and migration tasks from linked clone to full clone and add the machines to Horizon Manual Desktop Pool.
    Before using, make sure that the "Remote Power Policy" on the source desktop pool is set to "Take no power action."

.DESCRIPTION
    This PowerShell script is created by Ofir Dalal, an EUC Specialist at TeraSky EUC Company, for Amdocs.

.NOTES
    Copyright (c) 2023 Ofir Dalal. All rights reserved.

.COMPANY
    TeraSky EUC Company
    Website: https://www.terasky.com/

.COPYRIGHT
    Copyright (c) 2023 Ofir Dalal. All rights reserved.
    This script may not be reproduced or redistributed without permission from the author.

#>

# Task 1: Import the computers list from text file
$computers = Get-Content -Path "C:\temp\computers.txt" # replace with correct txt file location

# Task 2: Move each computer from existing OU to another OU with specific credentials.
$sourceOU = "OU=SourceOU,DC=domain,DC=com" # replace with source OU
$targetOU = "OU=TargetOU,DC=domain,DC=com" # replace with target OU
$userName = "domain\adminuser" # replace with permitted account
$credentials = Get-Credential -Credential $userName
foreach ($computer in $computers) {
    Move-ADObject -Identity "CN=$computer,$sourceOU" -TargetPath $targetOU -Credential $credentials
}

# Task 3: Connect to vCenter with specific credentials and input parameters.
$vCenterServer = "vcenter.domain.com" # replace with VDI vCetner
$vCenterUsername = "vcenteruser" #  Replace with the permitted account
$vCenterPassword = "vcenterpassword" # Replace with the password of permitted account
$clusterName = "ClusterName" # Replace with the name of your cluster
$Datastore = "vsandatastore" # replace with specific datastore
$folderPath = "ManualPool"  # Replace with the desired folder path

Connect-VIServer -Server $vCenterServer -Username $vCenterUsername -Password $vCenterPassword 

# Task 4: Shutdown each source VM from the text file
# Shutdown each source VM
foreach ($computer in $computers) {
    Write-Host "Shutting down VM: $computer"
    Shutdown-VMGuest $computer -Confirm:$false
}

# Wait for VM shutdown to complete
do {
    $poweredOffVMs = Get-VM -Name $computers | Where-Object {$_.PowerState -eq 'PoweredOff'}
    Write-Host "Checking if VMs are powered off..."
    Start-Sleep -Seconds 10
} while ($poweredOffVMs.Count -ne $computers.Count)             

 

# Task 5: Rename each source VM and append _old from the text file
foreach ($computer in $computers) {
    $oldName = $computer
    $newName = $computer + "_old"
    Get-VM -Name $oldName | Set-VM -Name $newName -Confirm:$false
}

# Task 6: Clone each source VM to new folder from the text file
# Get the cluster and its hosts
$cluster = Get-Cluster -Name $clusterName
$hosts = Get-Cluster $cluster | Get-VMHost

# Check folder path
$folder = Get-Folder -Name $folderPath -ErrorAction SilentlyContinue


# Clone each source VM to a random host in the cluster
foreach ($computer in $computers) {
    $sourceVM = $computer + "_old"
    $targetVM = $computer
    
    Write-Host "Cloning VM: $sourceVM"
    
    $vm = Get-VM -Name $sourceVM
    
    # Select a random host from the cluster
    $randomHost = $hosts | Get-Random
    
    $cloneParams = @{
        Name = $targetVM
        VM = $vm
        Location = $folder
        VMHost = $randomHost
        Datastore = $Datastore
    }
    
    New-VM @cloneParams
    
    # Wait for the clone operation to complete
    do {
        Start-Sleep -Seconds 10
        $cloneStatus = Get-Task | Where-Object {$_.Name -eq 'CloneVM_Task' -and $_.State -eq 'Running'}
    } while ($cloneStatus)
}


# Task 7: Remove the network card from the source VM from the text file
foreach ($computer in $computers) {
    $sourceVM = $computer + "_old"
    $networkAdapter = Get-NetworkAdapter -VM $sourceVM
    Remove-NetworkAdapter -NetworkAdapter $networkAdapter -Confirm:$false
}


# Task 8: Remove the hard disk 2 from each target virtual mchine
# Iterate over each target virtual machine
foreach ($computer in $computers) {
    $targetVM = $computer
    
    # Get the target virtual machine
    $vm = Get-VM -Name $targetVM
    
    # Get the second virtual hard disk
    $hardDisk = Get-HardDisk -VM $vm | Select-Object -Index 0
    
    if ($hardDisk) {
        Write-Host "Deleting second virtual hard disk from VM: $targetVM"
        
        # Remove the second virtual hard disk
        Remove-HardDisk -HardDisk $hardDisk -DeletePermanently -Confirm:$false
    }
}

# Task 9: Add a note on each source VM indicating that the machine has been migrated from the text file
foreach ($computer in $computers) {
    $sourceVM = $computer + "_old"
    $note = "Machine has been migrated"
    Set-VM -VM $sourceVM -Description $note -Confirm:$false
}

# Task 10: Connect to Horizon View with specific credentials and input parameters.
$horizonServer = "cs.domain.local"  # replace with horizon view serverURL
$horizonUsername = "domain\username"  # replace with permitted account
$horizonPassword = "password"  # replace with password of permitted account
$fullCloneManualPool = "fullclonepool"  # replace with full clone manual desktop pool
$linkedClonePool = "linkedclonepool" # replace with linked clone desktop pool
Connect-HVServer -Server $horizonServer -Username $horizonUsername -Password $horizonPassword 

# Task 11: Add each cloned machine to Manual Pool from the text file
foreach ($computer in $computers) {
    $clonedMachine = $computer
    add-hvdesktop -PoolName $fullCloneManualPool -Machines $clonedMachine
}

Start-Sleep 5

# Task 12: Assign user to each cloned machine on the manual pool
foreach ($computer in $computers) {
    $oldcomputer = $computer + "_old"
    $getusername = Get-HVMachineSummary -PoolName $linkedClonePool -MachineName $oldcomputer
    $username = $getusername.NamesData.UserName
Get-HVMachine -MachineName $computer | Set-HVMachine -User $username
}

# Task 13: Entitle user to the Full Clone Manual Pool
foreach ($computer in $computers) {
    $oldcomputer = $computer + "_old"
    $getusername = Get-HVMachineSummary -PoolName $linkedClonePool -MachineName $oldcomputer
    $username = $getusername.NamesData.UserName
    New-HVEntitlement -User $username -ResourceName $fullCloneManualPool -ResourceType Desktop 
}

# Task 14: Remove entitlement from Linked Clone Desktop pool
foreach ($computer in $computers) {
    $oldcomputer = $computer + "_old"
    $getusername = Get-HVMachineSummary -PoolName $linkedClonePool -MachineName $oldcomputer
    $username = $getusername.NamesData.UserName
    Remove-HVEntitlement -User $username -ResourceName $linkedClonePool -ResourceType Desktop
}