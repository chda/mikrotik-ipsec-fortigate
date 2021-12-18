# Mikrotik IPSec setup script
# This script is free software
# Tested on RouterOS 6.46.5
{
    # Name of ip address list with local networks
    :local lanlist LAN
    # Name of ip address list with trusted local ip addresses
    # Only workstations from this list can access headquarters resources
    :local trustedlist TRUSTED
    # Name of ip address list with headquarters networks
    :local ipseclist IPSEC
    # Tag for autoconfigured objects
    :local ipsecname headquarters
    # Distance for routes to headquarters networks
    # (must be less than distance from DHCP)
    :local defaultdistance 2
    # IP address of headquarters router
    # You can put default value here
    # (for example - :local gate 123.45.67.89)
    :local gate
    # Pre-shared key
    # You can put default value here
    # (for example - :local secret "VeryStrongKey1")
    :local secret
    :local user
    :local password
    # Filename prefixes for backup files
    :local backupbefore "before-ipsec-setup"
    :local backupafter "after-ipsec-setup"

    # Subroutine for keyboard input
    :local read do={ :return }
    # Subroutine for finding files
    :local findfile do={
        :local found false
        :foreach line in=[ /file print as-value where type=$type ] do={
            :if ( ! $found ) do={
                :local filename ( $line->"name" )
                :while ( [ :len [ :find $filename "/" ] ] > 0 ) do={
                    :set filename [ :pick $filename ( [ :find $filename "/" ] + 1 ) 999 ]
                }
                :if ( [ :find $filename $prefix ] = 0 ) do={
                    :set found true
                }
            }
        }
        :return $found
    }

    # Here we start
    :put "Looking for full backup..."
    :if ( [ $findfile prefix=$backupbefore type="backup" ] ) do={
        :put "... found old full backup"
    } else={
        :put "... not found. Doing full backup..."
        /system backup save dont-encrypt=yes name=$backupbefore
    }
    :put "Looking for script backup..."
    :if ( [ $findfile prefix=$backupbefore type="script" ] ) do={
        :put "... found old script backup"
    } else={
        :put "... not found. Doing script backup..."
        /export file=$backupbefore
    }

    # lanlist must be not empty or we'll got problems
    :put "Starting setup..."
    /ip firewall address-list
    :if ( [ :len [ find list=$lanlist ] ] = 0 ) do={
        add list=$lanlist address=127.0.0.1
    }

    # Check DNS
    :put "Validating DNS setup..."
    :if ( ( [ :len [ /ip dns get dynamic-servers ] ] = 0 ) and \
          ( [ :len [ /ip dns get servers ] ] = 0 ) ) do={
        /ip dns set servers="1.1.1.1,8.8.8.8"
    }
    /ip dns cache flush

    # Define gate variable
    :put "Looking for peer IP..."
    /ip ipsec peer
    :if ( [ :len [ find name=$ipsecname ] ] = 1 ) do={
        :set gate [ get [ find name=$ipsecname ] address ]
        :put ( "... found. Using old peer address: " . $gate )
    }
    :if ( [ :len $gate ] = 0 ) do={
        :put "... not found"
        :put "Enter IPSec peer IP address or FQDN"
        :set gate [ $read ]
    }
    :if ( [ :ping $gate count=2 ] < 1 ) do={
        :error ( "ERROR: Can't ping " . $gate . \
                 ". Check internet connection and start again." )
    }

    # Define secret, user name and password
    :put "Looking for credentials..."
    :local asksecret true
    :if ( [ :len $secret ] > 0 ) do={
        :set asksecret false
        :put "Using default PSK"
    }
    /ip ipsec identity
    :if ( [ :len [ find peer=$ipsecname ] ] = 1 ) do={
        :put "... found"
        :set secret [ get [ find peer=$ipsecname ] secret ]
        :set user [ get [ find peer=$ipsecname ] username ]
        :set password [ get [ find peer=$ipsecname ] password ]
        :put "Using old PSK, user name and password"
    }
    :if ( ( [ :len $user ] = 0 ) or \
          ( [ :len $password ] = 0 ) or \
          ( [ :len $secret ] = 0 ) ) do={
        :put "... not found"
        :local correct "n"
        :while ( $correct != "y" ) do={
            :if ( $asksecret ) do={
                :put "Enter group key (PSK)"
                :set secret [ $read ]
            }
            :put "Enter user name"
            :set user [ $read ]
            :put "Enter password"
            :set password [ $read ]
            :put ""
            :if ( $asksecret ) do={
                :put ( "PSK is \"" . $secret . "\"" )
            }
            :put ( "Username is \"" . $user . "\"" )
            :put ( "Password is \"" . $password . "\"" )
            :put "Is this correct\? (y|n)"
            :set correct [ $read ]
            :if ( $correct = "y" or $correct = "Y" ) do={
                :put "OK!"
            } else={
                :put "Suppose it was \"no\". Please repeat"
            }
        }
    }

    # Start cleaning old config
    :put "Cleaning old IPSec config..."
    remove [ find peer=$ipsecname ]
    /ip ipsec
    policy remove [ find group=$ipsecname ]
    peer remove [ find name=$ipsecname ]
    proposal remove [ find name=$ipsecname ]
    profile remove [ find name=$ipsecname ]
    mode-config remove [ find name=$ipsecname ]
    policy group remove [ find name=$ipsecname ]

    # Configure ipsec
    # You can adjust algorithms and other parameters here
    :put "Creating new IPSec config..."
    policy group add name=$ipsecname
    mode-config add name=$ipsecname responder=no src-address-list=$lanlist \
        connection-mark=$ipsecname
    profile add name=$ipsecname dh-group=modp2048 enc-algorithm=aes-256 \
        hash-algorithm=sha1 dpd-interval=2m dpd-maximum-failures=5 \
        lifetime=1d nat-traversal=yes proposal-check=obey
    peer add name=$ipsecname profile=$ipsecname exchange-mode=main \
        send-initial-contact=yes address=$gate
    proposal add name=$ipsecname pfs-group=modp2048 auth-algorithms=sha1 \
        enc-algorithms=aes-256-cbc,aes-256-gcm lifetime=30m
    identity add peer=$ipsecname policy-template-group=$ipsecname \
        mode-config=$ipsecname auth-method=pre-shared-key-xauth \
        generate-policy=port-strict secret=$secret username=$user \
        password=$password
    policy add group=$ipsecname proposal=$ipsecname dst-address=0.0.0.0/0 \
        src-address=0.0.0.0/0 protocol=all template=yes

    # Define interface to internet (interface we can access headquarters)
    :put "Determining internet gateway..."
    :local internetif ( [ /ip route check 1.1.1.1 once as-value ]->"interface" )
    :local internetgw [ /ip route get [ find dst-address=0.0.0.0/0 \
        active=yes ] gateway ]

    # Acquire IP addresses for trusted list if no one is set
    :put "Looking for trusted address list..."
    /ip firewall address-list
    :if ( [ :len [ find list=$trustedlist ] ] = 0 ) do={
        :foreach i in=[ /user active find ] do={
            :local ip [ /user active get $i address ]
            :if ( [ :len [ find list=$trustedlist address=$ip ] ] = 0 ) do={
                add list=$trustedlist address=$ip
            }
        }
    }

    # Permit only trusted sources to reach headquarters
    :put "Adding firewall rules for trusted IP..."
    # Make DHCP leases static
    /ip firewall address-list
    :foreach i in=[ find list=$trustedlist ] do={
        :local ip [ get $i address ]
        :if ( ( [ :typeof $ip ] = "ip" ) and \
              ( [ :len [ /ip dhcp-server lease find dynamic=yes \
                         address=$ip ] ] = 1 ) ) do={
            /ip dhcp-server lease make-static [ find dynamic=yes address=$ip ]
        }
    }
    # Cleanup
    /ip firewall filter
    remove [ find dst-address-list=$ipseclist out-interface=$internetif ]
    # Find place in ACL to put new lines
    :local place "nowhere"
    :foreach line in=[ print as-value where chain=forward ] do={
        :if ( ( $place = "nowhere" ) and \
              ( $line->"action" = "accept" ) and \
              ( [ :len [ :find ( $line->"connection-state" ) \
                         "established" ] ] > 0 ) ) do={
            :set place "after"
        } else={
            :if ( $place = "after" ) do={
                :set place ( $line->".id" )
            }
        }
    }
    :if ( [ :typeof $place ] != "id" ) do={
        :set place 0
    }
    add chain=forward action=accept log=no \
        comment="Permit traffic from trusted IP to headquarters network" \
        out-interface=$internetif src-address-list=$trustedlist \
        dst-address-list=$ipseclist place-before=$place
    add chain=forward action=reject log=yes log-prefix="Block untrusted" \
        reject-with=icmp-net-prohibited \
        comment="Reject traffic from untrusted IP to headquarters network" \
        out-interface=$internetif dst-address-list=$ipseclist \
        place-before=$place

    # Configure mangle to stop fasttracking ipsec
    :put "Creating blackhole bridge..."
    /interface bridge
    :if ( [ :len [ find name=$ipsecname ] ] = 0 ) do={
        add name=$ipsecname protocol-mode=none
    }
    :put "Fasttrack workaround..."
    /ip firewall filter
    :if ( [ :len [ find action=fasttrack-connection disabled=no ] ] > 0 ) do={
        :foreach i in=[ find action=fasttrack-connection disabled=no ] do={
            :if ( [ :len [ get $i connection-mark ] ] = 0 ) do={
                set $i connection-mark=( "!" . $ipsecname )
            }
        }
    }
    /ip firewall mangle
    remove [ find action=mark-routing chain=prerouting \
        dst-address-list=$ipseclist ]
    add action=mark-routing chain=prerouting new-routing-mark=$ipsecname \
        dst-address-list=$ipseclist connection-mark=$ipsecname passthrough=yes
    remove [ find action=mark-connection chain=forward \
             dst-address-list=$ipseclist out-interface=$ipsecname ]
    add action=mark-connection chain=forward dst-address-list=$ipseclist \
        out-interface=$ipsecname new-connection-mark=$ipsecname passthrough=no
    remove [ find action=mark-connection chain=forward ipsec-policy="in,ipsec" ]
    add action=mark-connection chain=forward ipsec-policy=in,ipsec \
        new-connection-mark=$ipsecname passthrough=no

    # Next steps we should make only when IPSec connection is established
    :local ready false
    :local try 1
    :while ( ( ! $ready ) and ( $try <= 5 ) ) do={
        :put ( "Waiting peer (try=" . $try . ")..." )
        :set try ( $try + 1 )
        :delay 3
        :if ( [ :len [ /ip ipsec policy find dynamic=yes \
                       peer=$ipsecname ] ] > 0 ) do={
            :set ready true
        }
    }
    :if ( ! $ready ) do={
        :error ( "ERROR: Can't establish IPSec peer with " . $gate . \
                 ". Check credentials and start again." )
    }
    :put "IPSec connection established!"
    :put "Continuing setup..."
    # Wait for all dynamic rules
    :delay 3

    # Configure local networks for dynamic NAT rules
    :put "Building local address list..."
    /ip firewall address-list
    remove [ find list=$lanlist ]
    :if ( [ :len [ /ip firewall address-list find list=$lanlist ] ] = 0 ) do={
        :local netlist [ /ip route find gateway!=$internetgw ]
        :local ipsecnetlist [ /ip ipsec policy find peer=$ipsecname ]
        :foreach i in=$netlist do={
            :local net [ /ip route get $i dst-address ]
            :local inipsec false
            :foreach ipsecnet in=$ipsecnetlist do={
                :if ( [ /ip ipsec policy get $ipsecnet \
                        dst-address ] = $net ) do={
                    :set inipsec true
                }
            }
            :if ( ! $inipsec ) do={
                :local ip $net
                :if ( [ :typeof $ip ] = "ip-prefix" ) do={
                    :set ip [ :pick $ip 0 [ :find $ip "/" ] ]
                }
                :if ( ( ( $ip & 255.0.0.0 ) = 10.0.0.0 ) or \
                    ( ( $ip & 255.224.0.0 ) = 172.16.0.0 ) or \
                    ( ( $ip & 255.255.0.0 ) = 192.168.0.0 ) ) do={
                    :if ( [ :len [ /ip firewall address-list find \
                                   list=$lanlist address=$net ] ] = 0 ) do={
                        /ip firewall address-list add list=$lanlist \
                            address=$net
                    }
                }
            }
        }
    }

    # Acquire headquarters network list
    :put "Building headquarters address list..."
    /ip firewall address-list
    remove [ find list=$ipseclist ]
    :foreach i in=[ /ip ipsec policy find peer=$ipsecname dynamic=yes ] do={
        :local remotenet [ /ip ipsec policy get $i dst-address ]
        :if ( [ :len [ find list=$ipseclist address=$remotenet ] ] = 0 ) do={
            add list=$ipseclist address=$remotenet
        }
    }

    # Add routes
    :put "Adding routes..."
    /ip route
    :foreach i in=[ /ip firewall address-list find list=$ipseclist ] do={
        :local net [ /ip firewall address-list get $i address ]
        remove [ find static=yes gateway=$internetgw dst-address=$net ]
        remove [ find static=yes gateway=$ipsecname dst-address=$net ]
        add gateway=$ipsecname dst-address=$net distance=$defaultdistance
    }

    # Filter unencrypted output to grey IP into internet
    # If sometime IPSec peer will be broken,
    # all inter-LAN traffic will be pushed into internet unencrypted.
    # So we need to filter it
    # I don't know how to do such filter with current RouterOS :(

    :put "Doing script backup..."
    /export file=$backupafter
    :put "... done"

    :put "******************************"
    :put ( "Check /ip firewall address-list for \"" . $trustedlist . "\" list" )
    :put "Only workstations from this list can access headquarters IPSec"
    /ip firewall address-list print where list=$trustedlist
    
    :put "SETUP COMPLETED SUCCESSFULLY!"
}
