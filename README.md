# CitrixADC-O365Endpoints
Get O365 Endpoint subnets from Microsoft endpoint JSON feed and create/bind Citrix ADC (NetScaler) Intranet Applications  

For use when using Citrix Gateway reverse split tunneling

Depending on Mode:
    info: Output information on the required intranet apps and compare to existing inranet apps.
    Command: Output the commands required to add and bind these intranet apps.
    Auto: Auto create O365 endpoint intranet apps and auto bind them to the specified binding object
    
.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -Mode info -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret"

Gives an overview of intranet apps for o365 endpoints and whether they currently exist

.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -Mode command -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret" -BindingType group -BindingObject "o365-users"

Creates a command set to add endpont intranet applications and bind them to an AAA group called "o365-users"

.EXAMPLE
& '.\CitrixADC-O365Endpoints.ps1' -NSIPProtocol http -auto command -NSIP 10.10.10.10 -user nitro -pass "SshhhItsASecret" -BindingType vserver -BindingObject "Vsrv_Gateway"

Creates a command set to add o365 endpont intranet applications and bind them to a vserver called "Vsrv_Gateway"

