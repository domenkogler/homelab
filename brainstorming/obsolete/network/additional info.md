## Additional Information Needed
- Current VLAN configuration (if any) on rb4011
Will be analyzed in provided config file (rb4011_config.rsc)

- Internet connection speed (up/down)
1G/1G

- Whether Comtrend can be bridged or must remain as router
Contrend is bridged, it is not serving as a router. RB 4011 is providing routing and establish PPPoE connection for internet access

- Number of IoT devices and their protocols (WiFi 2.4GHz only? Zigbee via HomeAssistant?)
Some devices are 2.4GZ only, but all APs have both radios, so this should not be a problem.

- Does "geoblocked content" require specific Slovenian IP, or just non-local-country IP?
just slovenian IP. But i would prefer using my static home IP address.

- VPS provider and approximate specs (CPU, RAM, storage, bandwidth)
propose specs

- Domain name(s) availability for services
I have TLD for use

- Are there children requiring parental controls?
yes, will propably need use some DNS service solution. Propose some of them.

- UPS situation for critical infrastructure?
I have UPS at home