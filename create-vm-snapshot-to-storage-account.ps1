<#
    .DESCRIPTION
        Creates a snapshot of a given VM and copies it to a different storage account
        In this context it is being used to copy an image of a XenApp server from the 
        production (UK South) to DR Azure region (UK West).  The image can then be used 
        to create a new VM which can be used as the basis to spin up XenApp servers in
        the DR region. 

    .NOTES
        AUTHOR: Dave Lee
        LASTEDIT: Jan 11, 2018
#>

# Provide the subscription Id
#$subscriptionId = ""

# The Master/Golden Image VM Name
$masterVM = "AZ-XA-TEMP"

# The resource group containing the Master/Golden image VM
$resourceGroupName ="rg-temp"

# The name that we'll use for the temporary snapshot
$snapshotname = "azauto_imagecopy_snapshot_" + (Get-Date -Format "yyyymmdd_HHmm")

# Provide storage account name where you want to copy the snapshot. 
$storageAccountName = "xenappimagestorage"

# Name of the storage container where the downloaded snapshot will be stored
$storageContainerName = "masterimage"

# Provide the key of the storage account where you want to copy snapshot. 
$storageAccountKey = ""

# Provide the name of the VHD file to which snapshot will be copied.
$destinationVHDFileName = "masterimage_osDisk.vhd"


# Connect to Azure using the Automation Account
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Now take a snapshot and copy it to the target storage account
try
{
    # Create a snapshot of the OS Disk for the Master/Golden Image VM
    $vm = Get-AzureRmVM -ResourceGroupName $resourceGroupName -Name $masterVM
    $osDisk = Get-AzureRmDisk -ResourceGroupName $vm.ResourceGroupName -DiskName $vm.StorageProfile.osDisk.Name
    $snapshotConfig = New-AzureRmSnapshotConfig -SourceUri $osDisk.Id -CreateOption Copy -Location $osdisk.Location
    Write-Output "Creating VM snapshot..."
    $snapshot = New-AzureRmSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotname -ResourceGroupName $osDisk.ResourceGroupName

    # Provide Shared Access Signature (SAS) expiry duration in seconds e.g. 3600.
    # Know more about SAS here: https://docs.microsoft.com/en-us/azure/storage/storage-dotnet-shared-access-signature-part-1
    $sasExpiryDuration = "3600"

    # Generate the SAS for the snapshot 
    $sas = Grant-AzureRmSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $Snapshot.Name -DurationInSecond $sasExpiryDuration -Access Read 
     
    # Create the context for the storage account which will be used to copy snapshot to the storage account 
    $destinationContext = New-AzureStorageContext –StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey  

    # Copy the snapshot to the storage account 
    Write-Output "Starting the copy process..."
    Write-Output Get-Date
    $copyStartTime = Get-Date
    $blobCopy = Start-AzureStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $destinationVHDFileName -Force

    # Wait for the file to be copied over to the target storage account.
    Write-Output "Waiting for copy process to complete..."
    $blobCopy | Get-AzureStorageBlobCopyState -WaitForComplete
    $copyEndTime = Get-Date
    
    # Print some summary info
    $duration = ($copyEndTime - $copyStartTime).TotalMinutes
    $gbCopied = ([math]::Round(($blobCopy.Length / 1024 / 1024 / 1024)))
    Write-Output "A total of $gbCopied GB was copied and took $duration minutes"

    # Revoke access to the snapshot and then remove it
    Revoke-AzureRmSnapshotAccess -ResourceGroupName $ResourceGroupName -SnapshotName $Snapshot.Name 
    Remove-AzureRmSnapshot -ResourceGroupName $resourceGroupName -SnapshotName $snapshot.name -Force
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}



