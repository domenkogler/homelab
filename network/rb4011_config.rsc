# 2026-06-24 09:25:58 by RouterOS 7.23.1
# software id = CAMI-MRKU
#
# model = RB4011iGS+
# serial number = B8F60AF69B05
/interface bridge add admin-mac=74:4D:28:8D:45:BF auto-mac=no comment=defconf name=bridge port-cost-mode=short
/interface bridge add name=bridge-guest port-cost-mode=short
/interface bridge add disabled=yes name=bridge-rti port-cost-mode=short
/interface pppoe-client add add-default-route=yes disabled=no interface=ether1 name=pppoe-telekom user=dkogler
/caps-man security add authentication-types=wpa-psk,wpa2-psk name=kogler-iot
/caps-man security add authentication-types="" name=kogler-guest
/caps-man security add authentication-types=wpa-psk,wpa2-psk name=kogler
/caps-man configuration add country=slovenia datapath.bridge=bridge name=cfg_Kogler-IOT security=kogler-iot ssid="Kogler IOT"
/caps-man configuration add country=slovenia datapath.bridge=bridge-guest .local-forwarding=no name=cfg_Kogler-guest security=kogler-guest ssid="Kogler guest"
/caps-man configuration add country=slovenia datapath.bridge=bridge hide-ssid=yes name=cfg_kogler security=kogler ssid=Kogler
/interface list add comment=defconf name=WAN
/interface list add comment=defconf name=LAN
/interface lte apn set [ find default=yes ] ip-type=ipv4 use-network-apn=no
/interface wireless security-profiles set [ find default=yes ] supplicant-identity=MikroTik
/iot lora servers add address=eu.mikrotik.thethings.industries name=TTN-EU protocol=UDP
/iot lora servers add address=us.mikrotik.thethings.industries name=TTN-US protocol=UDP
/iot lora servers add address=eu1.cloud.thethings.industries name="TTS Cloud (eu1)" protocol=UDP
/iot lora servers add address=nam1.cloud.thethings.industries name="TTS Cloud (nam1)" protocol=UDP
/iot lora servers add address=au1.cloud.thethings.industries name="TTS Cloud (au1)" protocol=UDP
/iot lora servers add address=eu1.cloud.thethings.network name="TTN V3 (eu1)" protocol=UDP
/iot lora servers add address=nam1.cloud.thethings.network name="TTN V3 (nam1)" protocol=UDP
/iot lora servers add address=au1.cloud.thethings.network name="TTN V3 (au1)" protocol=UDP
/iot wiliot servers set *1 address=mqtt.us-east-2.prod.wiliot.cloud name="Wiliot US East"
/ip pool add name=dhcp_pool-10.10.1 ranges=10.10.1.100-10.10.1.250
/ip pool add name=dhcp_pool-10.10.250 ranges=10.10.250.100-10.10.250.250
/ip pool add name=dhcp_pool-10.10.10 ranges=10.10.10.230-10.10.10.240
/ip dhcp-server add add-arp=yes address-pool=dhcp_pool-10.10.1 always-broadcast=yes interface=bridge lease-time=10m name=dhcp-10.10.1 use-radius=accounting
/ip dhcp-server add address-pool=dhcp_pool-10.10.250 interface=bridge-guest lease-time=10m name=dhcp-10.10.250
/ip dhcp-server
# Interface not running
add add-arp=yes address-pool=dhcp_pool-10.10.10 interface=bridge-rti name=dchp-10.10.10
/ip smb users set [ find default=yes ] disabled=yes
/user-manager user add attributes=Mikrotik-Group:full name=domen
/zerotier set zt1 disabled=no disabled=no
/caps-man manager set enabled=yes
/caps-man provisioning add action=create-dynamic-enabled master-configuration=cfg_kogler name-format=prefix-identity name-prefix=kogler-iot slave-configurations=cfg_Kogler-IOT,cfg_Kogler-guest
/dude set enabled=yes
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether2 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether3 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether4 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether5 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether6 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether7 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether8 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether9 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=ether10 internal-path-cost=10 path-cost=10
/interface bridge port add bridge=bridge comment=defconf ingress-filtering=no interface=sfp-sfpplus1 internal-path-cost=10 path-cost=10
/ip firewall connection tracking set udp-timeout=10s
/ip neighbor discovery-settings set discover-interface-list=all
/ip settings set max-neighbor-entries=8192
/ipv6 settings set disable-ipv6=yes max-neighbor-entries=8192 soft-max-neighbor-entries=8191
/interface list member add comment=defconf interface=bridge list=LAN
/interface list member add comment=defconf interface=ether1 list=WAN
/interface list member add interface=pppoe-telekom list=WAN
/interface list member add interface=*33 list=LAN
/interface list member add interface=*40 list=LAN
/interface list member add interface=*42 list=LAN
/interface list member add interface=bridge-rti list=LAN
/interface list member add interface=ether6 list=LAN
/interface list member add interface=*D6 list=LAN
/interface ovpn-server server add auth=sha1,md5 mac-address=FE:F0:A6:76:B1:67 name=ovpn-server1
/ip address add address=10.10.1.1/24 comment=defconf interface=bridge network=10.10.1.0
/ip address add address=10.10.250.1/24 interface=bridge-guest network=10.10.250.0
/ip address add address=10.255.1.1/24 interface=*D6 network=10.255.1.0
/ip address add address=10.255.2.1/24 interface=*40 network=10.255.2.0
/ip address add address=10.255.4.1/24 interface=*42 network=10.255.4.0
/ip address add address=192.168.1.2/24 interface=ether1 network=192.168.1.0
/ip address add address=10.10.10.1/24 interface=ether6 network=10.10.10.0
/ip arp add address=10.10.1.132 interface=bridge mac-address=00:1B:21:13:12:15
/ip cloud set back-to-home-vpn=enabled ddns-enabled=yes ddns-update-interval=10m
/ip cloud back-to-home-user add allow-lan=yes comment="Bela\C4\8Deva router" name="Naprava A54 uporabnika Domen" public-key="Fp71RRIKtmX2SvL8lorvzwY8ggKisE9APLDWU1BqN1o="
/ip cloud back-to-home-user add allow-lan=yes comment="router | RB4011iGS+" file-access=full file-access-path=/ name="Naprava A54 uporabnika Domen" public-key="CSqqVJwqvleXJGoa7CNN9RIrnnhs59lpGHJ2jqxCTiU="
/ip cloud back-to-home-user add allow-lan=yes comment="router | RB4011iGS+" file-access=full file-access-path=/ name="Naprava A54 uporabnika Domen" public-key="4MBE20H2YK4jcIK8opBWIrkThLb/5aldlqAbCFvgUFg="
/ip dhcp-client add interface=ether1 name=ether1
/ip dhcp-server config set store-leases-disk=never
/ip dhcp-server lease add address=10.10.1.99 client-id=1:70:85:c2:2d:6f:4 mac-address=70:85:C2:2D:6F:04 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.2 client-id=1:74:4d:28:f0:31:9a mac-address=74:4D:28:F0:31:9A server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.117 client-id=1:74:bf:c0:cd:33:b comment=Tiskalnik mac-address=74:BF:C0:CD:33:0B server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.49 client-id=1:1c:98:ec:e:d:3a comment="gen8 ILO" mac-address=1C:98:EC:0E:0D:3A server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.113 client-id=1:b8:27:eb:b1:81:c mac-address=B8:27:EB:B1:81:0C server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.4 client-id=1:6c:3b:6b:7d:b9:c5 mac-address=6C:3B:6B:7D:B9:C5 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.3 client-id=1:64:d1:54:aa:24:d1 mac-address=64:D1:54:AA:24:D1 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.106 comment="Shelly orhideje" mac-address=50:02:91:B0:AF:05 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.105 comment="Shelly WC" mac-address=50:02:91:B0:B2:4E server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.104 comment="Shelly kuhinja" mac-address=50:02:91:B0:AD:A6 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.110 comment=klima mac-address=2C:2B:F9:22:BA:DD server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.60 client-id=1:92:47:15:4:eb:49 mac-address=92:47:15:04:EB:49 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.123 client-id=1:ec:71:db:5f:bc:c1 comment="Reolink gara\C5\BEa" mac-address=EC:71:DB:5F:BC:C1 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.107 comment=klima mac-address=2C:2B:F9:23:41:EC server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.5 client-id=1:c4:ad:34:42:f1:7d mac-address=C4:AD:34:42:F1:7D server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.50 comment=gen8 mac-address=1C:98:EC:0E:0D:38 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.103 mac-address=10:52:1C:07:8E:D5 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.6 client-id=1:c4:ad:34:42:f0:b9 mac-address=C4:AD:34:42:F0:B9 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.116 client-id=1:30:56:84:35:0:dc comment="tablica Valentina" mac-address=30:56:84:35:00:DC server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.112 comment="Shelly kopalnica" mac-address=50:02:91:B0:DE:C4 server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.122 client-id=1:e4:5f:1:26:ef:aa mac-address=E4:5F:01:26:EF:AA server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.109 comment="UPS 3000" mac-address=00:20:85:C0:92:FA server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.118 client-id=1:0:a:b3:27:5f:8b comment="GIRA IP Router" mac-address=00:0A:B3:27:5F:8B server=dhcp-10.10.1
/ip dhcp-server lease add address=10.10.1.138 client-id=1:0:a:b3:29:2c:9e comment="GIRA X1" mac-address=00:0A:B3:29:2C:9E server=dhcp-10.10.1
/ip dhcp-server network add address=10.10.1.0/24 gateway=10.10.1.1
/ip dhcp-server network add address=10.10.10.0/24 dns-server=1.1.1.1,8.8.8.8 gateway=10.10.10.1
/ip dhcp-server network add address=10.10.250.0/24 dns-server=1.1.1.1,8.8.8.8 gateway=10.10.250.1
/ip dhcp-server network add address=192.168.88.0/24 comment=defconf dns-server=192.168.88.1 gateway=192.168.88.1
/ip dns set allow-remote-requests=yes servers=1.1.1.1,8.8.8.8
/ip dns static add address=10.10.1.1 comment=defconf name=rb4011.lan type=A
/ip dns static add address=10.10.1.2 name=switch.lan type=A
/ip dns static add address=10.10.1.50 name=nas.lan type=A
/ip dns static add address=10.10.1.122 name=homeassistant.local type=A
/ip dns static add address=10.10.10.220 name=srv type=A
/ip dns static add address=10.10.1.40 name=proxmox.local type=A
/ip dns static add address=10.10.1.114 name=ccu3-webui.local type=A
/ip firewall filter add action=accept chain=input comment=WireGuard dst-port=13231 protocol=udp
/ip firewall filter add action=accept chain=input comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
/ip firewall filter add action=accept chain=input dst-address=10.10.1.40
/ip firewall filter add action=drop chain=input comment="defconf: drop invalid" connection-state=invalid log=yes log-prefix=invalid
/ip firewall filter add action=accept chain=input comment="defconf: accept ICMP" protocol=icmp
/ip firewall filter add action=accept chain=input comment="defconf: accept to local loopback (for CAPsMAN)" dst-address=127.0.0.1
/ip firewall filter add action=drop chain=input comment="defconf: drop all not coming from LAN" in-interface-list=!LAN log=yes log-prefix="drop !LAN"
/ip firewall filter add action=accept chain=forward comment="defconf: accept in ipsec policy" ipsec-policy=in,ipsec
/ip firewall filter add action=accept chain=forward comment="defconf: accept out ipsec policy" ipsec-policy=out,ipsec
/ip firewall filter add action=fasttrack-connection chain=forward comment="defconf: fasttrack" connection-state=established,related
/ip firewall filter add action=accept chain=forward comment="defconf: accept established,related, untracked" connection-state=established,related,untracked
/ip firewall filter add action=drop chain=forward comment="defconf: drop invalid" connection-state=invalid log=yes log-prefix="drop invalid"
/ip firewall filter add action=drop chain=forward comment="defconf: drop all from WAN not DSTNATed" connection-nat-state=!dstnat connection-state=new in-interface-list=WAN log=yes log-prefix="drop forward"
/ip firewall nat add action=masquerade chain=srcnat comment="defconf: masquerade" ipsec-policy=out,none out-interface-list=WAN
/ip firewall nat add action=dst-nat chain=dstnat disabled=yes dst-port=8123 in-interface-list=WAN protocol=tcp to-addresses=10.10.1.122 to-ports=8123
/ip firewall nat add action=dst-nat chain=dstnat disabled=yes dst-port=80 in-interface-list=WAN protocol=tcp to-addresses=10.10.1.99
/ip firewall nat add action=src-nat chain=srcnat comment=NTP protocol=udp src-port=123 to-addresses=10.10.1.1
/ip ipsec profile set [ find default=yes ] dpd-interval=2m dpd-maximum-failures=5
/ip route add disabled=yes distance=1 dst-address=192.168.88.0/24 gateway="" pref-src="" routing-table=main scope=30 target-scope=10
/ip route add disabled=yes distance=1 dst-address=0.0.0.0/0 gateway=ether1 pref-src="" routing-table=main scope=30 target-scope=10
/ip service set ftp disabled=yes
/ip service set ssh disabled=yes
/ip service set telnet disabled=yes
/ip service set www address=10.0.0.0/8
/ip service set winbox address=10.0.0.0/8
/ip service set api address=10.0.0.0/8
/ip service set api-ssl disabled=yes
/ipv6 address add address=2a00:ee2:2700:8f01::1 interface=bridge
/ipv6 address add address=2a00:ee2:2700:8f00::1 interface=ether1
/ipv6 dhcp-client add add-default-route=yes interface=pppoe-telekom pool-name=pool_v6 pool-prefix-length=56 request=prefix use-peer-dns=no
/ipv6 firewall address-list add address=::/128 comment="defconf: unspecified address" list=bad_ipv6
/ipv6 firewall address-list add address=::1/128 comment="defconf: lo" list=bad_ipv6
/ipv6 firewall address-list add address=fec0::/10 comment="defconf: site-local" list=bad_ipv6
/ipv6 firewall address-list add address=::ffff:0.0.0.0/96 comment="defconf: ipv4-mapped" list=bad_ipv6
/ipv6 firewall address-list add address=::/96 comment="defconf: ipv4 compat" list=bad_ipv6
/ipv6 firewall address-list add address=100::/64 comment="defconf: discard only " list=bad_ipv6
/ipv6 firewall address-list add address=2001:db8::/32 comment="defconf: documentation" list=bad_ipv6
/ipv6 firewall address-list add address=2001:10::/28 comment="defconf: ORCHID" list=bad_ipv6
/ipv6 firewall address-list add address=3ffe::/16 comment="defconf: 6bone" list=bad_ipv6
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
/ipv6 firewall filter add action=drop chain=input comment="defconf: drop invalid" connection-state=invalid
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept ICMPv6" protocol=icmpv6
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept UDP traceroute" port=33434-33534 protocol=udp
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept DHCPv6-Client prefix delegation." dst-port=546 protocol=udp src-address=fe80::/10
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept IKE" dst-port=500,4500 protocol=udp
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept ipsec AH" protocol=ipsec-ah
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept ipsec ESP" protocol=ipsec-esp
/ipv6 firewall filter add action=accept chain=input comment="defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
/ipv6 firewall filter add action=accept chain=input comment="Accept www" dst-port=80 protocol=tcp
/ipv6 firewall filter add action=drop chain=input comment="defconf: drop everything else not coming from LAN" in-interface-list=!LAN
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept established,related,untracked" connection-state=established,related,untracked
/ipv6 firewall filter add action=drop chain=forward comment="defconf: drop invalid" connection-state=invalid
/ipv6 firewall filter add action=drop chain=forward comment="defconf: drop packets with bad src ipv6" src-address-list=bad_ipv6
/ipv6 firewall filter add action=drop chain=forward comment="defconf: drop packets with bad dst ipv6" dst-address-list=bad_ipv6
/ipv6 firewall filter add action=drop chain=forward comment="defconf: rfc4890 drop hop-limit=1" hop-limit=equal:1 protocol=icmpv6
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept ICMPv6" protocol=icmpv6
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept HIP" protocol=139
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept IKE" dst-port=500,4500 protocol=udp
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept ipsec AH" protocol=ipsec-ah
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept ipsec ESP" protocol=ipsec-esp
/ipv6 firewall filter add action=accept chain=forward comment="defconf: accept all that matches ipsec policy" ipsec-policy=in,ipsec
/ipv6 firewall filter add action=drop chain=forward comment="defconf: drop everything else not coming from LAN" in-interface-list=!LAN
/ipv6 nd set [ find default=yes ] advertise-dns=yes
/radius add address=127.0.0.1 require-message-auth=no service=ppp,login,hotspot,wireless,dhcp,ipsec,dot1x timeout=300ms
/radius incoming set accept=yes
/routing bfd configuration add disabled=no
/system clock set time-zone-name=Europe/Ljubljana
/system identity set name=router
/system logging add prefix=wg topics=wireguard
/system ntp client set enabled=yes
/system ntp server set enabled=yes manycast=yes use-local-clock=yes
/system ntp client servers add address=3.si.pool.ntp.org
/system ntp client servers add address=1.europe.pool.ntp.org
/system ntp client servers add address=2.europe.pool.ntp.org
/system routerboard settings
# Firmware upgraded successfully, please reboot for changes to take effect!
set auto-upgrade=yes boot-delay=9s
/tool mac-server set allowed-interface-list=LAN
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool netwatch add disabled=no down-script="/interface wireguard peer disable 0\r\
    \n:delay 5\r\
    \n/interface wireguard peer enable 0" host=10.255.1.2 interval=1m timeout=1s type=simple
/tool netwatch add disabled=no down-script="/interface wireguard peer disable 1\r\
    \n:delay 5\r\
    \n/interface wireguard peer enable 1" host=10.255.2.2 interval=1m timeout=1s type=simple
/tool netwatch add disabled=no down-script="/interface wireguard peer disable 2\r\
    \n:delay 5\r\
    \n/interface wireguard peer enable 2" host=10.255.3.2 interval=1m timeout=1s type=simple
/tool netwatch add disabled=no down-script="/interface wireguard peer disable 3\r\
    \n:delay 5\r\
    \n/interface wireguard peer enable 3" host=10.255.4.2 interval=1m timeout=1s type=simple
/tool romon set enabled=yes
/user aaa set use-radius=yes
/user-manager set enabled=yes
/user-manager router add address=10.10.1.2 name=switch
/user-manager router add address=10.10.1.3 name=AP-dnevna
/user-manager router add address=10.10.1.4 name=AP-garaza
/user-manager router add address=10.10.1.5 name=AP-spalnica
/user-manager router add address=127.0.0.1 name=lohalhost
