# Create a simple cluster using mostly defaults.
New-AzResourceGroup -Name AKSResourceGroup -Location eastus
$wid = New-AzOperationalInsightsWorkspace -Location eastus -Name akslogs -Sku PerGB2018 -ResourceGroupName AKSResourceGroup
mkdir C:\Users\Brian\.ssh\
$aksCluster = New-AzAksCluster -ResourceGroupName AKSResourceGroup -Name myAKSCluster -NodeCount 1 -GenerateSshKey -WorkspaceResourceId $wid

# Get a reference to the new AKSVNet
$AKSvnet = Get-AzVirtualNetwork -Name (get-azresource -ResourceType "Microsoft.Network/virtualNetworks" -ResourceGroupName $aksCluster.NodeResourceGroup).Name -ResourceGroupName $aksCluster.NodeResourceGroup

# Peer the new AKS Vnet with the Hub
# Peer hub to AKS
Add-AzVirtualNetworkPeering -Name HubtoAKSSpoke -VirtualNetwork $VNetHub -RemoteVirtualNetworkId $AKSvnet.Id -AllowGatewayTransit
# Peer AKS to hub
Add-AzVirtualNetworkPeering -Name AKSSpoketoHub -VirtualNetwork $AKSvnet -RemoteVirtualNetworkId $VNetHub.Id -AllowForwardedTraffic -UseRemoteGateways

# Extract the address space used by the AKS VNet
$VNetAKSPrefix = $AKSvnet.AddressSpace.AddressPrefixes[0]

## Create the routes

#  +-------+
#  | AKS   |
#  |VNet   |_______
#  +-------+       |    +--------+     +---------+
#                  |____| Hub    |     | On Prem |
#  +-------+      ______| VNet   |_____| VNet    |
#  |Server |______|     |        |     |         |
#  |VNet   |            |        |     |         |
#  +-------+            +--------+     +---------+

# The previous "1 - Build Basic Network.ps1" script created a rule for traffic from the on-prem network to the HubVNet to be routed via the Firewall private IP address.
# We don't need to add or change that - it's good as it is.
# We don't need to add any routing from the Hub to the AKS/Server VNets - this is done automatically by the network peering.

# We do need to create a custom route in the AKS VNet subnet to make sure all outgoing traffic is routed via the Firewall.
# Create a custom routing table, with BGP route propagation disabled. The property is now called "Virtual network gateway route propagation," but the API still refers to the parameter as "DisableBgpRoutePropagation."
$routeTableAKStoHub = New-AzRouteTable -Name 'UDR-AKS-To-Hub' -ResourceGroupName $aksCluster.NodeResourceGroup -location $aksCluster.Location -DisableBgpRoutePropagation

#Create a route
$routeTableAKStoHub | Add-AzRouteConfig -Name "ToFirewall" -AddressPrefix 0.0.0.0/0 -NextHopType "VirtualAppliance" -NextHopIpAddress $AzfwPrivateIP | Set-AzRouteTable

#Associate the route table to the subnet
#####
#####
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $AKSvnet -Name "aks-subnet" -AddressPrefix $VNetAKSPrefix -RouteTable $routeTableAKStoHub | Set-AzVirtualNetwork
#####
#####


## Add firewall rules to connect to the cluster.
$Rule1 = New-AzFirewallNetworkRule -Name "AllowApplication1" -Protocol TCP -SourceAddress $SNOnpremPrefix -DestinationAddress $VNetAKSPrefix -DestinationPort 30000

$NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 300 -Rule $Rule1 -ActionType "Allow"
$Azfw.NetworkRuleCollections = $NetRuleCollection
Set-AzFirewall -AzureFirewall $Azfw

# Connect
Import-AzAksCredential -ResourceGroupName AKSResourceGroup -Name myAKSCluster

# Add and application
kubectl apply -f vote.yaml
kubectl get service azure-vote-front --watch
