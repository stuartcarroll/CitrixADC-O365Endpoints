<#
O365 Endpoint for Citrix ADC (NetScaler)

Stu Carroll - Coffee Cup Solutions (stu.carroll@coffeecupsolutions.com) 2020
#>

<#
.SYNOPSIS
Get O365 Endpoint subnets from Microsoft endpoint JSON feed and get existing Citrix ADC (NetScaler) Intranet Applications. Depending on Mode:
    info: Output information on the required intranet apps and compare to existing inranet apps.
    Command: Output the commands required to add and bind these intranet apps.
    Auto: Auto create O365 endpoint intranet apps and auto bind them to the specified binding object.
.DESCRIPTION
.PARAMETER mode
Select mode of script to detemine the script actions:
 	info - Output intranet app info
	auto - Create intranet apps on the NetScaler
	command - Show commands requied to create intranet apps 
.PARAMETER NSIPProtocol
Select communication protocol with Citrix ADC - defaults to 'https'
.PARAMETER NSIP
NEtScaler IP address for Cirix ADC
.PARAMETER user
Citrix ADC System user for authentication
.PARAMETER pass
Citrix ADC System user password for authentication - deafults to 'info'
	For Info or Command mode this system user can have a 'read-only' commane policy
	For auto a custom command policy can be used but superuser will also work (not recommended)
.PARAMETER $IAPrefix
The prexif to add to the name of the intranet application - defaults to 'IA_O365_'
.PARAMETER IAprotocol
Intranet App protocoL - default "Any"
.PARAMETER BindingType
Binding type - AAA Group or VServer (if empty IAs wont be bound)
.PARAMETER BindingObject
Binding object - Name of AAA Group or VServer (if empty IAs wont be bound)
.PARAMETER ports
Intranet Application Port - defaults to '443'

.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -Mode info -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret"
Gives an overview of intranet apps for o365 endpoints and whether they currently exist
.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -Mode command -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret" -BindingType group -BindingObject "o365-users"
Creates a command set to add endpont intranet applications and bind them to an AAA group called "o365-users"
.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -auto command -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret" -BindingType vserver -BindingObject "Vsrv_Gateway"
Creates a command set to add o365 endpont intranet applications and bind them to a vserver called "Vsrv_Gateway"

#>

#Decalre parameters
param(  
    #Script mode:
    # info - Output intranet app info
    # auto - Create intranet apps on the NetScaler
    # command - Show commands requied to create intranet apps 
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet('info', 'command', 'auto')]
    [String]$Mode = "info",
    #NSIP protocol
    [Parameter(Position = 1, Mandatory = $true)]
    [ValidateSet('http', 'https')]
    [String]$NSIPProtocol = "https",
    #NetSCaler NSIP Address
    [Parameter(Position = 2, Mandatory = $true)]
    [string]$NSIP,
    #NetScaler system user
    # For Info or Command mode this system user can have a 'read-only' commane policy
    # For auto a custom command policy can be used but superuser will also work (not recommended)
    [Parameter(Position = 3)]
    [string]$user,
    #NetScaler system password
    [Parameter(Position = 4)]
    [string]$pass,
    #O365 Intranet App variables
    #Prefix for Intranet Application Name
    [Parameter(Position = 5)]
    [string]$IAPrefix = "IA_O365_",
    #Intranet App protocoL - default "Any"
    [Parameter(Position = 6)]
    [string]$IAprotocol = "ANY",
    #Binding type - AAA Group or VServer (if empty IAs wont be bound)
    [Parameter(Position = 7)]
    [ValidateSet('vserver', 'group')]
    [String]$BindingType,  
    #Binding object - Name of AAA Group or VServer (if empty IAs wont be bound)
    [Parameter(Position = 8)]
    [String]$BindingObject,  
    #Intranet application port (to be revised to take protocol from endpoints.office.com)
    [Parameter(Position = 9)]
    [string]$ports = "443"
)

#Declare variables
$MSUrl = "https://endpoints.office.com/endpoints/worldwide?clientrequestid="

#Authenticate NetScaler Session
$payload = @{
    "login" = @{ 
        "username" = $user; 
        "password" = $pass     
    } 
}       

Invoke-RestMethod -Uri  $NSIPProtocol"://"$NSIP"/nitro/v1/config/login" -Method POST -Body ($payload | ConvertTo-Json ) -SessionVariable Session -Headers @{"Content-Type" = "application/vnd.com.citrix.netscaler.login+json" }
$Script:Session = $Local:Session

#Get existing Intranet Apps from NetScaler
$IAs = (Invoke-RestMethod -Uri  $NSIPProtocol"://"$NSIP"/nitro/v1/config/vpnintranetapplication" -Method GET -WebSession $Session -Headers @{"Content-Type" = "application/vnd.com.citrix.netscaler.login+json" }).vpnintranetapplication

#Check IAs is not null
if ($null -eq $IAs) {
    Write-Error "No data retreieved from NITRO - PROTECT THE USERS! ABANDON SHIP!"
    Exit 
}

#Create subnet table
$SubNetTable = New-Object System.Data.DataTable
$SubNetTable.Columns.Add("IAName", "string") | Out-Null
$SubNetTable.Columns.Add("Subnet", "string") | Out-Null
$SubNetTable.Columns.Add("CIDR", "int32") | Out-Null
$SubNetTable.Columns.Add("Mask", "string") | Out-Null
$SubNetTable.Columns.Add("Exists", "Boolean") | Out-Null
$SubNetTable.Columns.Add("Existing", "array") | Out-Null
$SubNetTable.Columns.Add("Command", "array") | Out-Null

#Get Subnets from Microsoft 
$ep = Invoke-RestMethod ($MSUrl + ([GUID]::NewGuid()).Guid) 
$destPrefix = $ep | Where-Object { $_.category -eq "Optimize" } | Select-Object -ExpandProperty ips | Where-Object { $_ -like '*.*' }

#Check ep is not null
if ($null -eq $destPrefix) {
    Write-Error "No data retreieved from endpoints.office.com - PROTECT THE USERS! ABANDON SHIP!"
    Exit 
}

#Build SubNet Table
$destPrefix | ForEach-Object ( $_ ) {
    #Clear previous results 
    $Existing = @()
    $Command = @()

    #Split subnet with CIDR notation
    $subnet = ($_).split("/")

    #Convert CIDR to Mask
    $mask = ([Math]::Pow(2, $subnet[1]) - 1) * [Math]::Pow(2, (32 - $subnet[1]))
    $bytes = [BitConverter]::GetBytes([UInt32] $mask)
    $netmask = (($bytes.Count - 1)..0 | ForEach-Object { [String] $bytes[$_] }) -join "."

    #Check if intranet App exists
    $Exists = if ($IAs | Where-Object { $_.destip -eq $subnet[0] -and $_.netmask -eq $netmask }) {
            $true
            #Find existing intranet apps with the same desintation IP and netmask
            foreach ($IA in $IAs | Where-Object { $_.destip -eq $subnet[0] -and $_.netmask -eq $netmask }) {     
                $Existing += $IA.intranetapplication
            }
        }
        else {
            #Give up and go home
            $false
        }
    #If Does not exist write the command to create IA into Command variable
    if ($Exists -eq $false) {
        $IACommand = 'add vpn intranetApplication "' + $IAPrefix + $subnet[0] + '_' + $subnet[1] + '" ' + $IAprotocol + " " + $subnet[0] + " -netmask " + $netmask + " -destPort " + $ports + " -interception TRANSPARENT"
        $Command += $IACommand
        if ($BindingType -eq "group") {
            $BindCommand = 'bind aaa group "' + $BindingObject + '" -intranetapplicaiton "' + $IAPrefix + $subnet[0] + "_" + $subnet[1] + '"'
            $Command += $BindCommand
        }
        elseif ($BindingType -eq "vserver") {
            $BindCommand = 'bind vpn vserver "' + $BindingObject + '" -intranetapplicaiton "' + $IAPrefix + $subnet[0] + "_" + $subnet[1] + '"'
            $Command += $BindCommand
        }
        else{
        #No binging to be done   
        }

    }
    else {
        #If it exists then no command is required
        $Command = "N/A"
    }
    
    #Create a new row in table
    $r = $SubNetTable.NewRow()
    $r.IAName = $IAPrefix + $subnet[0] + "_" + $subnet[1]
    $r.Subnet = $subnet[0]
    $r.CIDR = $subnet[1]
    $r.Mask = $netmask
    $r.Exists = $Exists
    $r.Existing = $Existing
    $r.Command = $Command
    $SubNetTable.Rows.Add($r)
}
            
#Script result:
switch ($mode) {
    "info" {
        #Output information 
        $SubNetTable | Format-Table
    }
    "command" {
        #Output commands to manually create intranet apps 
        Write-Output "Commands to impelement Intranet Apps"
        $subnettable | Select-Object command | Where-Object { $_.command -ne "N/A" } | Select-Object -ExpandProperty command
    }
    "auto" {
        $SubNetTable | Format-Table
        #If auto create intranet apps that dont exist and bind to binding object
        write-host "Creating Intranet Apps!" -ForegroundColor Yellow
        foreach ($newIA in $SubNetTable | Where-Object { $_.Exists -eq $false }) {
            #Automatically create intranet applications
            #Buiid intranet app payload
            Write-Host $newIA.IAname
            $payload = @{
                
                "vpnintranetapplication" = @{
                    "intranetapplication" = $newIA.IAname;
                    "destip"              = $newIA.subnet
                    "netmask"             = $newIA.mask;
                    "protocol"            = $IAprotocol;
                    "destport"            = $ports;
                    "interception"        = "transparent";
                        
                }
            }   
            #Create intranet app
            Write-Host "Creating"$newIA.IAname
            Invoke-RestMethod -Uri  $NSIPProtocol"://"$NSIP"/nitro/v1/config/vpnintranetapplication" -Method POST -Body ($payload | ConvertTo-Json )  -WebSession $Session -Headers @{"Content-Type" = "application/json" }
            
            #Bind Intranet App to object
            #Find Intranet Apps bound to the binding object

            switch($BindingType) {
            
                "Group" {
                    write-host "Binding "$newIA.IAname" to "$BindingType" "$BindingObject
                    $payload = @{
                        "aaagroup_vpnintranetapplication_binding"=@{
                        "groupname" = $BindingObject;
                        "intranetapplication" = $newIA.ianame;
                            }
                        }
                        Invoke-RestMethod -Uri  $NSIPProtocol"://"$NSIP"/nitro/v1/config/aaagroup_vpnintranetapplication_binding" -Method PUT -Body ($payload | ConvertTo-Json ) -WebSession $Session -Headers @{"Content-Type"="application/json"}
                    }
                "VServer" {
                    write-host "Binding "$newIA.IAname" to "$BindingType" "$BindingObject
                    payload = @{
                        "vpnvserver_vpnintranetapplication_binding" = @{
                            "name"                = $BindingObject;
                            "intranetapplication" = $newIA.ianame;
                        }
                    }
                    Invoke-RestMethod -Uri  $NSIPProtocol"://"$NSIP"/nitro/v1/config/vpnvserver_vpnintranetapplication_bindingg" -Method PUT -Body ($payload | ConvertTo-Json ) -WebSession $Session -Headers @{"Content-Type" = "application/json" }         
                }
                default {
                    write-host "No Binding Stype has been specified. Intranet Apps will need to be bound manually."
                }
            }
        }
    }
}



