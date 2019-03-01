# Creates a Route Table and imports routes from a csv file which needs
# to be in the format:
#  routeName, nextHotType, nextHopIp, addressPrefix

Param(
    [parameter(mandatory)][string]$udrName,
    [parameter(mandatory)][string]$resourceGroup,
    [parameter(mandatory)][string]$location,
    [parameter(mandatory)][string]$tagName,
    [parameter(mandatory)][string]$tagValue,
    [parameter(mandatory)][string]$routeCsv
) 

#route array

$routesArray = @()


#add routes

$routes = Import-Csv $routeCsv

foreach ($route in $routes)
{
    $udrRoute = New-AzureRmRouteConfig -Name $route.routeName -NextHopType $route.nextHopType -NextHopIpAddress $route.nextHopIp -AddressPrefix $route.addressPrefix
    $routesArray += $udrRoute
}


#create udr

$udr = New-AzureRmRouteTable -Name $udrName `
    -ResourceGroupName $resourceGroup `
    -Location $location `
    -Route $routesArray `
    -Tag @{Name=$tagName;Value=$tagValue}