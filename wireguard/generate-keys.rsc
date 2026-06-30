# Run these commands ONE AT A TIME on the router to generate key pairs.
# Copy the output and fill in the placeholders in laptop.conf and phone.conf.
#
# The router's own key pair is generated automatically when the
# wireguard interface is created. Retrieve it with:
#
#   /interface wireguard print
#
# The command below generates a key pair for a peer (laptop or phone).
# Run it once per peer and save both the private + public key.

# --- For the LAPTOP ---
/interface wireguard peers
generate-key-pair

# Save the output:
#   private-key: <laptop-private-key>  → goes into laptop.conf [Interface]
#   public-key:  <laptop-public-key>   → goes into wireguard-server.rsc as <laptop-public-key>

# --- For the PHONE ---
/interface wireguard peers
generate-key-pair

# Save the output:
#   private-key: <phone-private-key>   → goes into phone.conf [Interface]
#   public-key:  <phone-public-key>    → goes into wireguard-server.rsc as <phone-public-key>