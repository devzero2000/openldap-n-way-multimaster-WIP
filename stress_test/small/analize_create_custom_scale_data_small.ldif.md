==============================================================================
ANALISI LDIF: create_custom_scale_data_small.ldif
==============================================================================

Entry totali: 318 Utenti: 100 Gruppi: 208 Altro: 10 Attributo membri:
member

Membri per gruppo (solo UTENTI diretti): count=208 min=0 max=15
media=6.67 mediana=7.0 dev.std=2.85

Membri per gruppo (solo GRUPPI nidificati): count=208 min=0 max=2
media=0.04 mediana=0.0 dev.std=0.24

Membri per gruppo (TOTALI, utenti+gruppi): count=208 min=1 max=15
media=6.71 mediana=7.0 dev.std=2.76

Distribuzione membri per gruppo: 0-0: 0 1-5: 66 6-10: 129 11-25: 13
26-50: 0 51-100: 0 101+: 0

Gruppi senza alcun membro: 0

Gruppi per utente (calcolato da member: sui gruppi): count=100 min=3
max=29 media=13.87 mediana=13.5 dev.std=5.35

Distribuzione gruppi per utente: 0-0: 0 1-5: 6 6-10: 24 11-25: 67 26-50:
3 51-100: 0 101+: 0

Coerenza memberOf vs member: (confronto per utente, non solo per
conteggio) Utenti con memberOf presente: 100/100

Gruppi per utente (calcolato da memberOf dichiarato): count=100 min=3
max=29 media=13.87 mediana=13.5 dev.std=5.35 Utenti con DISALLINEAMENTO
tra memberOf e member: 0

Utenti senza alcuna appartenenza a gruppi: 0

Annidamento gruppi: Gruppi con figli nidificati: 6 Profondita’ massima
catena: 5 Cicli rilevati: 0

Riferimenti pendenti (member: che punta a un DN inesistente nel file): 1
esempi: cn=administrators,ou=groups,dc=example,dc=com -\>
cn=admin,dc=example,dc=com

Gruppi con valori member: duplicati nella stessa entry: 0

objectClass piu’ frequenti: top 318 groupofnames 208 inetorgperson 100
organizationalunit 4 applicationprocess 4 dcobject 1 organization 1
device 1 pwdpolicy 1

Attributi piu’ frequenti: objectclass 318 structuralobjectclass 318
creatorsname 318 createtimestamp 318 entryuuid 318 entrycsn 318
modifiersname 318 modifytimestamp 318 cn 313 member 208 description 208
memberof 107 uid 100 sn 100 userpassword 100 pwdchangedtime 100 ou 4 o 1
dc 1 contextcsn 1

Attributi per entry: count=318 min=9 max=23 media=11.95 mediana=11.0
dev.std=1.58

Password: 100/100 utenti con userPassword impostata Schema di hashing:
SSHA 100

Profondita’ del DN: count=318 min=2 max=4 media=3.98 mediana=4.0
dev.std=0.16

Container (genitore del DN) piu’ popolati: 208
ou=groups,dc=example,dc=com 100 ou=people,dc=example,dc=com 4
dc=example,dc=com 4 ou=system,dc=example,dc=com 1 dc=com 1
ou=policies,dc=example,dc=com

Dimensione approssimata per entry (byte, somma valori attributi):
count=318 min=288 max=1669 media=702.45 mediana=651.0 dev.std=253.94

==============================================================================
