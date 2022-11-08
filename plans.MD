# Tervek

Olyan program eszköztár létrehozása, amely megkönnyíti a Linux rendszerek használatát.
Támogatni tervezett distrok: Debian, Ubuntu

# Támogatott featurek

## Szöveges fájlok feldolgozása
- OpenVPN connection log olvasó
- OpenVPN log olvasó
- iptables log olvasó

## OpenVPN community server kezelő
- Automata telepítés
- Módok közötti váltás: kulcs alapú authentikáció vagy felhasználónév/jelszó páros alapú authentikáció
- Webadmin nélküli kulcs alapú authentikációkor felhasználói kulcsok kezelése (létrehozás, revoke, kilistázás)
- Logbeállítások (connection log, stb)
- Webadmin felület a kezelésére (szerver leállítás, indítás, felcsatlakozott userek nézése; felhasználónév/jelszó párosok listázása, törlése, módosítása) - erre már van kész webadmin felület
- screenben futó szerver

## Apache, nginx kezelő
- Honlap hozzáadása (külön dir)
- Honlap törlése
- Reverse proxy kezelése
- SSL kezelése a honlapokon letsencrypt + certbot + dehydrated segítségével (HTTP-01 challenge, DNS-01 challenge, tls-alpn-01 challenge)

## Tűzfalkezelő (iptables)
- IPv4:
  - port nyitása
  - port zárása
  - bizonyos portra csak bizonyos IPről engedélyezni bejövő kapcsolatot
  - bizonyos IP-re csak bizonyos portra engedélyezni kimenő kapcsolatot
  - rate limit a portokra (hashlimit-et felhasználva)
  - OpenVPN NAT forward
  - network interface alapú szabályok támogatása
  - iptables ellenőrző (például X port engedélyezve van bejövő forgalomnak, azonban nincs letiltva minden más bejövő forgalom, tehát nem effektív a szabály -> ezt kijelezné)
  - ki-be kapcsolható togglek:
    - bejövő forgalom csak engedélyezettek közül jöhet be (ekkor például SSH portot automatikusan engedélyezne a connection drop elkerülése érdekében)
    - kimenő forgalom csak engedélyezett irányba mehet ki (ekkor például SSH portot automatikusan engedélyezne a connection drop elkerülése érdekében)
- IPv6: lásd IPv4
- Alternatíva: https://wiki.ubuntu.com/UncomplicatedFirewall


