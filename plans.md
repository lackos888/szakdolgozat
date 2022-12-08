# Tervek

Olyan program eszköztár létrehozása, amely megkönnyíti a Linux rendszerek használatát, szerver programok alapkonfigurációjának létrehozását.
Támogatni tervezett distrok: Debian, Ubuntu

# Támogatott featurek

## Interaktív felület
A program eszköztár interaktív felületen (TUI-on) keresztül működik, amelyhez a(z) https://github.com/tboox/ltui GitHub repo link alatt található library lesz felhasználva. Ez a library egy cross-platform library.

## Szöveges fájlok feldolgozása
- OpenVPN connection log olvasó
- OpenVPN log olvasó
- iptables log olvasó

## OpenVPN community server kezelő
- Telepítés
- Módok közötti váltás: kulcs alapú authentikáció vagy felhasználónév/jelszó páros alapú authentikáció
- Webadmin nélküli kulcs alapú authentikációkor felhasználói kulcsok kezelése (létrehozás, revoke, kilistázás)
- Logbeállítások (connection log, stb)
- Webadmin felület a kezelésére (szerver leállítás, indítás, felcsatlakozott userek nézése; előre generált openvpn config letöltése; felhasználónév/jelszó párosok listázása, törlése, módosítása) - erre már van kész webadmin felület
- screenben futó szerver

## Apache, nginx kezelő
- Telepítés
- Honlap hozzáadása (külön dir)
- Honlap törlése
- Reverse proxy kezelése
- SSL kezelése a honlapokon letsencrypt + certbot + dehydrated segítségével (HTTP-01 challenge, DNS-01 challenge, tls-alpn-01 challenge)

## Tűzfalkezelő (iptables)
- Telepítés ha nincs fent
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
  - hozzáadott/törölt szabályok kiírása az iptables megismerése érdekében
- IPv6: lásd IPv4
- Alternatíva: https://wiki.ubuntu.com/UncomplicatedFirewall

# Témakörhöz kapcsolódó dolgok

## Csomagkezelő Luaban
A Lua programozási nyelvhez létezik egy hasonló csomagkezelői program, mint az npm a Javascripthez. A csomagkezelő szintén nyílt forráskódú, és cross-platform. Maga a program szintén Lua programozási nyelven íródott.

- A csomagkezelő neve: LuaRocks
- Csomagkezelő GitHub repo linkje: https://github.com/luarocks/luarocks
- Lehetnek olyan csomagok, amelyek dependencykkel (függőségekkel) rendelkeznek
- Támogatja a csomagok ```build```elését, meg lehet nézni a csomagok dokumentációit (```doc```), fel lehet őket szimplán telepíteni (automatikus buildeléssel - ```install```), továbbá össze lehet egy csomagot a ```pack``` parancs segítségével tömöríteni, és egy ugyan olyan architektúrával rendelkező gépre fel lehet telepíteni az összetömörített fájlban lévő csomagot az ```install``` paranccsal.
- Ezen felül még számos parancsot tartalmaz, amelyet a 
```luarocks -h``` paranccsal tudunk megnézni.

## Csomagok felhasználása Luaban
A Lua programozási nyelvben a ```require``` funkció segítségével tudunk libraryket és egyéb dolgokat betölteni. Ez a funkció először is ellenőrzi a fájl megadott path-ját, majd pedig ellenőrzi, hogy be van-e már töltve a runtimeba. Ha már be van töltve, nem tölti be újra, hanem azt fogja visszaadni, amit először is visszaadott.
A ```require``` először betölti a fájlt, majd lefuttatja a benne lévő kódot, hasonlóan a ```dofile``` funkcióhoz. Visszatérési értéke függ a lefuttatott kód ```return``` parancsától. 

Példaként az ltui egy táblát ad vissza, amelyet fel lehet használni a következő módon:
```lua
local ltui        = require("ltui") --az ltui.lua-t fogja betolteni
local application = ltui.application
local event       = ltui.event
local rect        = ltui.rect
local window      = ltui.window
local demo        = application()

function demo:init()
    application.init(self, "demo")
    self:background_set("blue")
    self:insert(window:new("window.main", rect {1, 1, self:width() - 1, self:height() - 1}, "main window", true))
end

demo:run()
```
A LuaRocks segítségével feltelepített csomagok a ```require``` funkció segítségével könnyen betölthetőek, mivel a ```shared``` folderbe bekerülnek.

## Fájlkezelés Luaban
A Lua programozási nyelvhez tartozik egy IO "keretrendszer", ezen keretrendszer segítségével tudjuk a fájlokat kezelni. Maga a Lua-beli elérés neve is ```io```.

A C-hez hasonlóan a Luaban is File Handlek alapján működik a fájlok kezelése.

### Fájl megnyitása

Egy ilyen handlet a(z) ```io.open (filename [, mode])``` funkcióval nyithatunk meg. A megnyitási módok teljesen ugyan azok, mint a C nyelvben az ```fopen``` funkciónál használt módok. Sikeres megnyitás esetén egy file handlet ad vissza a funkció. Sikertelen megnyitás esetén pedig első értékként "nil"-lel tér vissza, a második érték a hiba szövege, a harmadik érték pedig a hiba kódja.

### Fájl bezárása

Egy megnyitott file handlet az ```io.close(filehandle/üres paraméter)```, vagy a ```filehandle:close()``` funkcióval zárhatunk be.
Az alapértelmezett output fájlt ```io.close()``` funkcióval tudjuk bezárni, amelynek nincsen paramétere.

### Alapértelmezett írásra, olvasásra kijelölt fájl megadása

A file handlet alapértelmezett olvasási vagy írási fájllá tehetjük a(z) ```io.input(fájlnév/filehandle)```, vagy a(z) ```io.output(fájlnév/filehandle)``` funkció segítségével.

### Fájlok "mutatójának" beállítása

Olvasás és írás előtt meg kell bizonyosodnunk róla, hogy jó pozíción van-e a fájl "mutatója".
Ezt a ```filehandle:seek([whence [, offset]])``` funkcióval tudjuk megtenni.
A whence paraméter lehet ```set``` (a pozíció a fájl elejétől kezdődik), ```cur``` (jelenlegi pozíció), ```end``` (fájl vége). Az offset megadja a relatív pozíció helyét a ```whence``` paramétertől függően. Hibamentes lefutás esetén visszaadja az új offsetet byteokban számolva, amit a fájl elejétől számol.

### Fájlok olvasása

Az ```io.read```, ```io.lines```, ```filehandle:read()```, ```filehandle:lines()``` funkciókkal tudjuk a fájlokat olvasni. 

Az ```io.read``` kizárólag az alapértelmezett olvasásra megadott fájlból olvas egy megadott forma alapján, az ```io.lines``` viszont egy fájlnevet vár paraméterként, és csak sorokat olvas be.
A ```filehandle:read()``` a megadott fájlból olvas (nem az alapértelmezett olvasásra kijelölt fájlból) egy megadott forma alapján.
A ```filehandle:lines()``` funkció szintén egy megadott fájlból olvas, azonban csak sorokat.
Az ```io.lines``` funkció bezárja a fájl végigolvasása után a handlet (mivel automatikusan nyitotta meg), azonban a ```filehandle:lines()``` funkció nem zárja be a fájl végigolvasása után a handlet.

A fájlokat ```read``` funkcióval olvasva meg kell adnunk, hogy milyen formátumot várunk el a beolvasástól:
```
*n - beolvas egy számot és visszaadja azt
*a - beolvassa a teljes fájlt a mostani pozíciótól
*l - (alapbeállítás) - kiolvassa a következő sort, ha elfogytak a sorok akkor nil-nel tér vissza
szám megadása esetén - beolvas annyi számú karaktert stringként, amit megadtunk. 
Ha 0-t adunk meg, akkor üres stringgel tér vissza, kivéve, ha fájl végén vagyunk, mert akkor hibával tér vissza a read.
```

### Fájlok írása

A fájlokba ```write``` funkció segítségével írhatunk. Működési elve nagyon egyszerű: ```io.write(string1, string2, ..., string)``` vagy ```filehandle:write(string1, string2, ..., string)```. A funkciók a fájl megnyitásának módját figyelembe véve működnek.

Ha űríteni szeretnénk az írási puffert (így egyből a fájl írása végrehajtódik) a(z) ```io.flush``` funkcióval tudjuk a default output file bufferjét üríteni, ```filehandle:flush()``` paranccsal pedig egy megadott fájlét.

