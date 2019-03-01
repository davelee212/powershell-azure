<#
    .DESCRIPTION
        Use to create a new VM based on a VHD that has been copied into a storage account 
        from the production site.  This was written as part of the DR/failover setup for
        Citrix on Azure

    .NOTES
        AUTHOR: Dave Lee
        LASTEDIT: Jan 14, 2018
#>

# Set the variables/locations to be used by the script
$resourceGroupName = "rg-xenimage-ukwest"
$location = "UKWest"
$sourceUri = "https://xxxxxxxx.blob.core.windows.net/masterimage/masterimage_osDisk.vhd"
$newVmName = "AZ-XA-TEMP"
$newVmSize = "Standard_DS4_v2"

$subnetName = "SN-10-12-1-0_24-lan"
$vnetName = "test_vnet"
$vnetResGroupName = "rg-xenimage-ukwest"

#$vnetName = "vn-10-12-0-0_16"
#$vnetResGroupName = "rg-network-ukwest"


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

# Now create the VM using the OS Disk in the storage account
try
{

    # Create a new Managed Disk from the VHD we have in the storage account blob container
    $osDiskName = $newVmName + '_osDisk'
    $osDisk = New-AzureRmDisk -DiskName $osDiskName -Disk (New-AzureRmDiskConfig -AccountType Standard_LRS -Location $location -CreateOption Import -SourceUri $sourceUri) -ResourceGroupName $resourceGroupName

    # Create a new NIC for the VM
    $vnet = Get-AzureRmVirtualNetwork -Name $vnetNAme -ResourceGroupName $vnetResGroupName
    $subnet = $vnet.Subnets | Where {$_.Name -eq $subnetName}
    $nicName = $newVmName + '_nic01'
    $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $location -SubnetId $subnet.Id

    # Create a new VM config
    $vmConfig = New-AzureRmVMConfig -VMName $newVmName -VMSize $newVmSize
    $vm = Add-AzureRmVMNetworkInterface -VM $vmConfig -Id $nic.Id
    $vm = Set-AzureRmVMOSDisk -VM $vm -ManagedDiskId $osDisk.Id -StorageAccountType Standard_LRS -DiskSizeInGB 128 -CreateOption Attach -Windows

    # Create the VM
    New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $location -VM $vm


}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}