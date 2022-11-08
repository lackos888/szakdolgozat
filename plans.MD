# Tervek

Olyan program eszköztár létrehozása, amely megkönnyíti a Linux rendszerek használatát.
Támogatni tervezett distrok: Debian, Ubuntu

# Támogatott featurek

## Tűzfalkezelő (iptables)
- IPv4:
  - port nyitása
  - port zárása
  - bizonyos portra csak bizonyos IPről engedélyezni bejövő kapcsolatot
  - bizonyos IP-re csak bizonyos portra engedélyezni kimenő kapcsolatot
  - rate limit a portokra (hashlimit-et felhasználva)
  - OpenVPN NAT forward
  - iptables ellenőrző (például X port engedélyezve van bejövő forgalomnak, azonban nincs letiltva minden más bejövő forgalom, tehát nem effektív a szabály -> ezt kijelezné)
  - ki-be kapcsolható togglek:
    - bejövő forgalom csak engedélyezettek közül jöhet be (ekkor például SSH portot automatikusan engedélyezne a connection drop elkerülése érdekében)
    - kimenő forgalom csak engedélyezett irányba mehet ki (ekkor például SSH portot automatikusan engedélyezne a connection drop elkerülése érdekében)
- IPv6: lásd IPv4
- Alternatíva: https://wiki.ubuntu.com/UncomplicatedFirewall


