# NSDynUpdate
Currently support IPv6 only
# DNS HA Configuration file, use the below syntax:
# Hostname 1st_Priority_IP 2nd_Priority_IP 3rd_Priority_IP...
# In case of using the LS (Load Balanced) version of the script priorities does not have meaning.
# If you delete entire record from here, you will need to restart named and remove the record from the zone file.
#hostname6        2001:abc::1::1a     2001:abc::1::1b
