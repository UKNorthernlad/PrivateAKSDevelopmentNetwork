# Login 
login-azaccount -TenantId <someGUID>
get-azsubscription -SubscriptionId <someGUID> | select-azsubscription

# Enable any required resource providers
Register-AzResourceProvider -ProviderNamespace Microsoft.VirtualMachineImages

# Declare the variables to create the 3 virtual networks.
$RG1 = "FW-Hybrid-Test"
$Location1 = "East US"

# Variables for the firewall hub VNet
$VNetnameHub = "VNet-hub"
$SNnameHub = "AzureFirewallSubnet"
$VNetHubPrefix = "10.5.0.0/16"
$SNHubPrefix = "10.5.0.0/24"
$SNGWHubPrefix = "10.5.1.0/24"
$GWHubName = "GW-hub"
$GWHubpipName = "VNet-hub-GW-pip"
$GWIPconfNameHub = "GW-ipconf-hub"
$ConnectionNameHub = "hub-to-Onprem"

# Variables for the spoke virtual network
$VnetNameSpoke = "VNet-Spoke"
$SNnameSpoke = "SN-Workload"
$VNetSpokePrefix = "10.6.0.0/16"
$SNSpokePrefix = "10.6.0.0/24"
$SNSpokeGWPrefix = "10.6.1.0/24"

# Variables for the on-premises virtual network
$VNetnameOnprem = "Vnet-Onprem"
$SNNameOnprem = "SN-Corp"
$VNetOnpremPrefix = "192.168.0.0/16"
$SNOnpremPrefix = "192.168.1.0/24"
$SNGWOnpremPrefix = "192.168.2.0/24"
$GWOnpremName = "GW-Onprem"
$GWIPconfNameOnprem = "GW-ipconf-Onprem"
$ConnectionNameOnprem = "Onprem-to-hub"
$GWOnprempipName = "VNet-Onprem-GW-pip"

$SNnameGW = "GatewaySubnet"


## Create the firewall hub virtual network
# create the resource group to contain the resources
New-AzResourceGroup -Name $RG1 -Location $Location1

# Define the subnets to be included in the virtual network:
$FWsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameHub -AddressPrefix $SNHubPrefix
$GWsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNGWHubPrefix

# Create the firewall hub virtual network:
$VNetHub = New-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG1 -Location $Location1 -AddressPrefix $VNetHubPrefix -Subnet $FWsub,$GWsub

# Request a public IP address to be allocated to the VPN gateway
$gwpip1 = New-AzPublicIpAddress -Name $GWHubpipName -ResourceGroupName $RG1 -Location $Location1 -AllocationMethod Dynamic

## Create the spoke virtual network
# Define the subnets to be included in the spoke virtual network:
$Spokesub = New-AzVirtualNetworkSubnetConfig -Name $SNnameSpoke -AddressPrefix $SNSpokePrefix
$GWsubSpoke = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNSpokeGWPrefix
# Create the spoke virtual network
$VNetSpoke = New-AzVirtualNetwork -Name $VnetNameSpoke -ResourceGroupName $RG1 -Location $Location1 -AddressPrefix $VNetSpokePrefix -Subnet $Spokesub,$GWsubSpoke


## Create the on-premises virtual network
# Define the subnets to be included in the virtual network:
$Onpremsub = New-AzVirtualNetworkSubnetConfig -Name $SNNameOnprem -AddressPrefix $SNOnpremPrefix
$GWOnpremsub = New-AzVirtualNetworkSubnetConfig -Name $SNnameGW -AddressPrefix $SNGWOnpremPrefix

# Create the "on-premises" virtual network:
$VNetOnprem = New-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG1 -Location $Location1 -AddressPrefix $VNetOnpremPrefix -Subnet $Onpremsub,$GWOnpremsub

# Request a public IP address to be allocated to the gateway
$gwOnprempip = New-AzPublicIpAddress -Name $GWOnprempipName -ResourceGroupName $RG1 -Location $Location1 -AllocationMethod Dynamic


##Configure and deploy the firewall
#Now deploy the firewall into the hub virtual network.
# Get a Public IP for the firewall
$FWpip = New-AzPublicIpAddress -Name "fw-pip" -ResourceGroupName $RG1 -Location $Location1 -AllocationMethod Static -Sku Standard
# Create the firewall
$Azfw = New-AzFirewall -Name AzFW01 -ResourceGroupName $RG1 -Location $Location1 -VirtualNetworkName $VNetnameHub -PublicIpName fw-pip

#Save the firewall private IP address for future use
$AzfwPrivateIP = $Azfw.IpConfigurations.privateipaddress
$AzfwPrivateIP

# Configure network rules
$Rule1 = New-AzFirewallNetworkRule -Name "AllowWeb" -Protocol TCP -SourceAddress $SNOnpremPrefix -DestinationAddress $VNetSpokePrefix -DestinationPort 80
$Rule2 = New-AzFirewallNetworkRule -Name "AllowRDP" -Protocol TCP -SourceAddress $SNOnpremPrefix -DestinationAddress $VNetSpokePrefix -DestinationPort 3389
$NetRuleCollection = New-AzFirewallNetworkRuleCollection -Name RCNet01 -Priority 100 -Rule $Rule1,$Rule2 -ActionType "Allow"
$Azfw.NetworkRuleCollections = $NetRuleCollection
Set-AzFirewall -AzureFirewall $Azfw

##Create and connect the VPN gateways
#The hub and "on-premises" virtual networks are connected via VPN gateways.
#Create a VPN gateway for the hub virtual network
$vnet1 = Get-AzVirtualNetwork -Name $VNetnameHub -ResourceGroupName $RG1
$subnet1 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet1
$gwipconf1 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameHub -Subnet $subnet1 -PublicIpAddress $gwpip1
New-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG1 -Location $Location1 -IpConfigurations $gwipconf1 -GatewayType Vpn -VpnType RouteBased -GatewaySku basic

# Create a VPN gateway for the on-premises virtual network
$vnet2 = Get-AzVirtualNetwork -Name $VNetnameOnprem -ResourceGroupName $RG1
$subnet2 = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet2
$gwipconf2 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfNameOnprem -Subnet $subnet2 -PublicIpAddress $gwOnprempip
New-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG1 -Location $Location1 -IpConfigurations $gwipconf2 -GatewayType Vpn -VpnType RouteBased -GatewaySku basic

# Create the VPN connections
$vnetHubgw = Get-AzVirtualNetworkGateway -Name $GWHubName -ResourceGroupName $RG1
$vnetOnpremgw = Get-AzVirtualNetworkGateway -Name $GWOnpremName -ResourceGroupName $RG1

# Start the connections
New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameHub -ResourceGroupName $RG1 -VirtualNetworkGateway1 $vnetHubgw -VirtualNetworkGateway2 $vnetOnpremgw -Location $Location1 -ConnectionType Vnet2Vnet -SharedKey 'AzureA1b2C3'
New-AzVirtualNetworkGatewayConnection -Name $ConnectionNameOnprem -ResourceGroupName $RG1 -VirtualNetworkGateway1 $vnetOnpremgw -VirtualNetworkGateway2 $vnetHubgw -Location $Location1 -ConnectionType Vnet2Vnet -SharedKey 'AzureA1b2C3'

# Verify the connection
Get-AzVirtualNetworkGatewayConnection -Name $ConnectionNameHub -ResourceGroupName $RG1


### Stop here is you want to create an AKS cluster in the spoke. See the tab "Add AKS Cluster".
### If you want a quick VM and all routing in place for testing, carry on below.


# Peer the hub and spoke virtual networks
# Peer hub to spoke
Add-AzVirtualNetworkPeering -Name HubtoSpoke -VirtualNetwork $VNetHub -RemoteVirtualNetworkId $VNetSpoke.Id -AllowGatewayTransit
# Peer spoke to hub
Add-AzVirtualNetworkPeering -Name SpoketoHub -VirtualNetwork $VNetSpoke -RemoteVirtualNetworkId $VNetHub.Id -AllowForwardedTraffic -UseRemoteGateways

## Create the routes
#A route from the hub gateway subnet to the spoke subnet through the firewall IP address
#A default route from the spoke subnet through the firewall IP address
#Create a route table
$routeTableHubSpoke = New-AzRouteTable -Name 'UDR-Hub-Spoke' -ResourceGroupName $RG1 -location $Location1

#Create a route
Get-AzRouteTable -ResourceGroupName $RG1 -Name UDR-Hub-Spoke | Add-AzRouteConfig -Name "ToSpoke" -AddressPrefix $VNetSpokePrefix -NextHopType "VirtualAppliance" -NextHopIpAddress $AzfwPrivateIP | Set-AzRouteTable
#Associate the route table to the subnet
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNetHub -Name $SNnameGW -AddressPrefix $SNGWHubPrefix -RouteTable $routeTableHubSpoke | Set-AzVirtualNetwork

#Now create the default route
#Create a table, with BGP route propagation disabled. The property is now called "Virtual network gateway route propagation," but the API still refers to the parameter as "DisableBgpRoutePropagation."
$routeTableSpokeDG = New-AzRouteTable -Name 'UDR-DG' -ResourceGroupName $RG1 -location $Location1 -DisableBgpRoutePropagation

#Create a route
Get-AzRouteTable -ResourceGroupName $RG1 -Name UDR-DG | Add-AzRouteConfig -Name "ToFirewall" -AddressPrefix 0.0.0.0/0 -NextHopType "VirtualAppliance" -NextHopIpAddress $AzfwPrivateIP | Set-AzRouteTable
#Associate the route table to the subnet
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $VNetSpoke -Name $SNnameSpoke -AddressPrefix $SNSpokePrefix -RouteTable $routeTableSpokeDG | Set-AzVirtualNetwork

## Create test virtual machines
# Create the workload virtual machine
# Create an inbound network security group rule for ports 3389 and 80
$nsgRuleRDP = New-AzNetworkSecurityRuleConfig -Name Allow-RDP  -Protocol Tcp -Direction Inbound -Priority 200 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix $SNSpokePrefix -DestinationPortRange 3389 -Access Allow

$nsgRuleWeb = New-AzNetworkSecurityRuleConfig -Name Allow-web  -Protocol Tcp -Direction Inbound -Priority 202 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix $SNSpokePrefix -DestinationPortRange 80 -Access Allow

# Create a network security group
$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $RG1 -Location $Location1 -Name NSG-Spoke02 -SecurityRules $nsgRuleRDP,$nsgRuleWeb

#Create the NIC
$NIC = New-AzNetworkInterface -Name spoke-01 -ResourceGroupName $RG1 -Location $Location1 -SubnetId $VnetSpoke.Subnets[0].Id -NetworkSecurityGroupId $nsg.Id

#Define the virtual machine
$VirtualMachine = New-AzVMConfig -VMName VM-Spoke-01 -VMSize "Standard_D2s_v3"
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName Spoke-01 -ProvisionVMAgent -EnableAutoUpdate


$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter' -Version latest

#Create the virtual machine
New-AzVM -ResourceGroupName $RG1 -Location $Location1 -VM $VirtualMachine -Verbose

#Install IIS on the VM
Set-AzVMExtension -ResourceGroupName $RG1 -ExtensionName IIS -VMName VM-Spoke-01 -Publisher Microsoft.Compute -ExtensionType CustomScriptExtension -TypeHandlerVersion 1.4 -SettingString '{"commandToExecute":"powershell Add-WindowsFeature Web-Server"}' -Location $Location1


## Create the on-premises virtual machine
New-AzVm -ResourceGroupName $RG1 -Name "VM-Onprem" -Location $Location1 -VirtualNetworkName $VNetnameOnprem -SubnetName $SNNameOnprem -OpenPorts 3389 -Size "Standard_DS2"


## Test the firewall
# 0 - Get the VM-spoke-01 private IP
#     $NIC.IpConfigurations.privateipaddress
# 1 - From the Azure portal, connect to the VM-Onprem virtual machine.
# 2 - Open a web browser on VM-Onprem, and browse to http://<VM-spoke-01 private IP>.
# 3 - You should see IIS default page.
