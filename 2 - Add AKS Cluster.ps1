# Create a simple cluster using mostly defaults.
New-AzResourceGroup -Name AKSResourceGroup -Location eastus
$wid = New-AzOperationalInsightsWorkspace -Location eastus -Name akslogs -Sku PerGB2018 -ResourceGroupName AKSResourceGroup
mkdir C:\Users\Brian\.ssh\
New-AzAksCluster -ResourceGroupName AKSResourceGroup -Name myAKSCluster -NodeCount 1 -GenerateSshKey -WorkspaceResourceId $wid

# Get a reference to the new AKSVNet
$AKSvnet = Get-AzVirtualNetwork -Name aks-vnet-36511838 -ResourceGroupName MC_AKSResourceGroup_myAKSCluster_eastus

# Peer the new AKS Vnet with the Hub
# Peer hub to AKS
Add-AzVirtualNetworkPeering -Name HubtoAKSSpoke -VirtualNetwork $VNetHub -RemoteVirtualNetworkId $AKSvnet.Id -AllowGatewayTransit
# Peer AKS to hub
Add-AzVirtualNetworkPeering -Name AKSSpoketoHub -VirtualNetwork $AKSvnet -RemoteVirtualNetworkId $VNetHub.Id -AllowForwardedTraffic -UseRemoteGateways

# Extract the address space used by the AKS VNet
$VNetAKSPrefix = $AKSvnet.AddressSpace.AddressPrefixes[0]

## Create the routes
#A route from the hub gateway subnet to the AKS subnet through the firewall IP address
#A default route from the AKS subnet through the firewall IP address
#Create a route table
$routeTableHubAKS = New-AzRouteTable -Name 'UDR-Hub-AKS' -ResourceGroupName $RG1 -location $Location1

#Create a route
Get-AzRouteTable -ResourceGroupName $RG1 -Name UDR-Hub-AKS | Add-AzRouteConfig -Name "ToAKS" -AddressPrefix $VNetAKSPrefix -NextHopType "VirtualAppliance" -NextHopIpAddress $AzfwPrivateIP | Set-AzRouteTable
#Associate the route table to the subnet
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNetHub -Name $SNnameGW -AddressPrefix $SNGWHubPrefix -RouteTable $routeTableHubSpoke | Set-AzVirtualNetwork

#Now create the default route
#Create a table, with BGP route propagation disabled. The property is now called "Virtual network gateway route propagation," but the API still refers to the parameter as "DisableBgpRoutePropagation."
$routeTableSpokeDG = New-AzRouteTable -Name 'UDR-DG' -ResourceGroupName $RG1 -location $Location1 -DisableBgpRoutePropagation

#Create a route
Get-AzRouteTable -ResourceGroupName $RG1 -Name UDR-DG | Add-AzRouteConfig -Name "ToFirewall" -AddressPrefix 0.0.0.0/0 -NextHopType "VirtualAppliance" -NextHopIpAddress $AzfwPrivateIP | Set-AzRouteTable
#Associate the route table to the subnet

Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNetSpoke -Name $SNnameSpoke -AddressPrefix $SNSpokePrefix -RouteTable $routeTableSpokeDG | Set-AzVirtualNetwork

## Add firewall rules to connect to the cluster.
$Rule1 = New-AzFirewallNetworkRule -Name "AllowApplication1" -Protocol TCP -SourceAddress $SNOnpremPrefix -DestinationAddress $VNetAKSPrefix -DestinationPort 80
$NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 300 -Rule $Rule1 -ActionType "Allow"
$Azfw.NetworkRuleCollections = $NetRuleCollection
Set-AzFirewall -AzureFirewall $Azfw

# Connect
Import-AzAksCredential -ResourceGroupName AKSResourceGroup -Name myAKSCluster

# Add and application
kubectl apply -f vote.yaml
kubectl get service azure-vote-front --watch
