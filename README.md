# IPSec setup for remote worker

## When and why
This script is supposed to be used by network admins for simplifing setup process in such cases:
- remote workers have Mikrotik routers with RouterOS at home offices
- headquarters have Fortigate firewall with FortiOS
- headquarters use Active Directory for user authentication
- secure connection is needed
- role based access control (user group based network access policies) is needed

## Quick start
Step 1. Configure Windows NPS for RADIUS service for Fortigate. Use vendor-specific attribute to put authenticated user into right user group at Fortigate as mentioned here https://inside.fortinet.com/doku.php?id=sslvpn_with_radius_using_active_directory_and_nps

Step 2. Configure IPSec dialup interface on Fortigate. Select Pre-Shared Key and XAUTH. Configure proposals to make possible use of hardware offloaded encryption at Mikrotik. See https://wiki.mikrotik.com/wiki/Manual:IP/IPsec#Hardware_acceleration

Step 3. Use any secure way to supply to remote workers:
- Fortigate IP address
- PSK
- user name with password (if user doesn't know)
- Mikrotik setup script (https://github.com/chda/mikrotik-ipsec-fortigate/edit/master/ipsec-setup.rsc)
- instructions for Mikrotik users

## Instructions for Mikrotik users
Step 1. Ensure you know Fortigate IP address, PSK, your user name and password

Step 2. Upgrade RouterOS to 6.46+

Step 3. Upload setup script (https://github.com/chda/mikrotik-ipsec-fortigate/blob/master/ipsec-setup.rsc) to Mikrotik router via Winbox, WebFig or SFTP

Step 4. Switch to terminal. Login as admin. Execute script
```
/import ipsec-setup.rsc
```
and follow onscreen instructions.

Step 5. Go to IP/Firewall/Address-list and adjust trusted IP addresses.

Step 6. Check IPSec connection.
