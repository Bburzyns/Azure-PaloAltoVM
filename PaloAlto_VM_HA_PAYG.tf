version of the AzureRM Provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "=3.19.1"
    }
  }
}

provider "azurerm" {
  features {}
  #ICN-VA-Network
  subscription_id = "xyz-xyz-xyz-xyz-xyz"
  tenant_id       = "xyz-xyz-xyz-xyz-xyz"
}


#
# VARIABLES
#

#lowercase only
variable "projectname" {
  default = "xyz"
}
variable "groupname" {
  default = "xyz-EME"
}
#variable "resourcegroup" {
#  default = "xyz"
#}
variable "location" {
  default = "xyz"
}
variable "fw_name" {
  default = "xyz-EME-PAN-FW"
}
#variable "IPAddressPrefix" {
#  default = "10.60"
# w konfiguracji subnetow statyczny tylko sufix
#}
variable VNETAddressSpace {
  default = ["192.168.52.0/22"]
}
variable ManagementSubnet {
  default = ["192.168.52.0/24"]
}
variable ExternalSubnet {
  default = ["192.168.53.0/24"]
}
variable InternalSubnet {
  default = ["192.168.54.0/24"]
}
variable "ExternalPrivateIP" {
  default = "192.168.53.4"
}
variable "InternalPrivateIP" {
  default = "192.168.54.4"
}


#
# resource Group
#

resource "azurerm_resource_group" "RG" {
  name     = "ICN-VA-${var.groupname}"
  location = "${var.location}"
  tags = {
    Owner = "xyz"
    Name = "xyz"
  }
}


#
# VNET
#

resource "azurerm_virtual_network" "vnet" {
  resource_group_name = "${azurerm_resource_group.RG.name}"
  location = "${var.location}"
  name = "${var.projectname}-vnet"
  address_space = "${var.VNETAddressSpace}"
  tags = {
    Owner ="xyz"
  }
}


resource "azurerm_subnet" "Management" {
  name = "Management_subnet"
  address_prefixes = "${var.ManagementSubnet}"
  resource_group_name = "${azurerm_resource_group.RG.name}"
  virtual_network_name = azurerm_virtual_network.vnet.name
}

resource "azurerm_subnet" "External" {
  name = "External_subnet"
  address_prefixes = "${var.ExternalSubnet}"
  resource_group_name = "${azurerm_resource_group.RG.name}"
  virtual_network_name = azurerm_virtual_network.vnet.name
}

resource "azurerm_subnet" "Internal" {
  name = "Internal_subnet"
  address_prefixes = "${var.InternalSubnet}"
  resource_group_name = "${azurerm_resource_group.RG.name}"
  virtual_network_name = azurerm_virtual_network.vnet.name
}


#
# PAN VM
#

# Storage for FW disk
resource "azurerm_storage_account" "PAN_FW_DISK" {
  name = "${var.projectname}pavmdisk"
  #name                = join("", list(var.StorageAccountName, substr(md5(azurerm_resource_group.PAN_FW_RG.id), 0, 4)))
  resource_group_name = "${azurerm_resource_group.RG.name}"
  location            = "${var.location}"
  account_replication_type = "LRS"
  account_tier        = "Standard" 
}

# Public IP for PAN mgmt Intf
resource "azurerm_public_ip" "pan_mgmt" {
  name                = "${var.projectname}-mgmt"
  location            = var.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method   = "Static"
  domain_name_label   = "${var.projectname}-management"
}

# Public IP for PAN external interface
resource "azurerm_public_ip" "pan_external" {
  name                = "${var.projectname}-external"
  location            = var.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method   = "Static"
  domain_name_label   = "${var.projectname}-external"
}

# PAN mgmt VNIC
resource "azurerm_network_interface" "FW_VNIC0" {
  name                = "${var.projectname}-fwmgmt0"
  location            = var.location
  resource_group_name = azurerm_resource_group.RG.name
  enable_accelerated_networking = true
  
  ip_configuration {
    name                          = "ipconfig0"
    subnet_id                     = azurerm_subnet.Management.id
    private_ip_address_allocation = "Dynamic"
    # Mgmt VNIC has static public IP address
    public_ip_address_id          = azurerm_public_ip.pan_mgmt.id
  }

  tags = {
    panInterface = "mgmt0"
  }
}


# PAN external VNIC
resource "azurerm_network_interface" "FW_VNIC1" {
  name                = "${var.projectname}-fwethernet1_1"
  location            = var.location
  resource_group_name = azurerm_resource_group.RG.name

  enable_accelerated_networking = true
  enable_ip_forwarding          = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.External.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ExternalPrivateIP
    # Untrusted interface has static public IP address
    public_ip_address_id          = azurerm_public_ip.pan_external.id
  }

  tags = {
    panInterface = "ethernet1/1"
  }
}

# PAN internal VNIC
resource "azurerm_network_interface" "FW_VNIC2" {
  name                = "${var.projectname}-fwethernet1_2"
  location            = var.location
  resource_group_name = azurerm_resource_group.RG.name
  
  enable_accelerated_networking = true
  enable_ip_forwarding          = true

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = azurerm_subnet.Internal.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.InternalPrivateIP
  }

  tags = {
    panInterface = "ethernet1/2"
  }
}

# PA Firewall VM
resource "azurerm_virtual_machine" "PAN_FW" {
  name = "${var.fw_name}"
  location = var.location
  resource_group_name = azurerm_resource_group.RG.name
  vm_size = "Standard_D3_v2"

  plan {
    #licenses: pay as you go: bundle2; purchased lic: byo1
    name = "bundle1"
    publisher = "paloaltonetworks"
    product = "vmseries1"
  }

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer = "vmseries1"
    sku = "bundle1"
    version = "Latest"    
  }

  storage_os_disk {
    name = "${var.projectname}-osDisk"
    vhd_uri = "${azurerm_storage_account.PAN_FW_DISK.primary_blob_endpoint}vhds/${var.fw_name}-osdisk1.vhd"
    caching = "ReadWrite"
    create_option = "FromImage"
  }


  os_profile {
    computer_name = "${var.fw_name}"
    admin_username = "admin"
    admin_password = "p2ssw0rd"
    
#    # pa initial config
#    custom_data = join(
#      ",",
#      [
#        "storage-account=xyz",
#        "access-key=xyz",
#       "file-share=bootstrap",
#        "share-directory=None"
#
#      ],
#    )

  }


  primary_network_interface_id = azurerm_network_interface.FW_VNIC0.id
  network_interface_ids = [azurerm_network_interface.FW_VNIC0.id,
                           azurerm_network_interface.FW_VNIC1.id,
                           azurerm_network_interface.FW_VNIC2.id ]

  os_profile_linux_config {
    disable_password_authentication = false
  }

}

output "Project_Name" {
  value = var.projectname
}

output "Location" {
  value = var.location
}

output "Firewall_Mgmt_FQDN" {
  value = azurerm_public_ip.pan_mgmt.fqdn
}

output "Firewall_Mgmt_IP" {
  value = azurerm_public_ip.pan_mgmt.ip_address
}

output "Firewall_External_FQDN" {
  value = azurerm_public_ip.pan_external.fqdn
}

output "Firewall_External_P" {
  value = azurerm_public_ip.pan_external.ip_address
}
