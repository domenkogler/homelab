# jan/02/1970 00:01:22 by RouterOS 7.6
# software id = QHLW-U7XP
#
# model = RBD52G-5HacD2HnD
# serial number = BEEB0BF61E5F
/interface wireless set [ find default-name=wlan1 ] ssid=MikroTik
/interface wireless set [ find default-name=wlan2 ] ssid=MikroTik
/interface wireless security-profiles set [ find default=yes ] supplicant-identity=MikroTik
/ip hotspot profile set [ find default=yes ] html-directory=hotspot
