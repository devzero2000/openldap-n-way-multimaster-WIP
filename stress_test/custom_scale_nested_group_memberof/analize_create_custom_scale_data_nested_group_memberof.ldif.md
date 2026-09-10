==============================================================================
ANALISI LDIF: create_custom_scale_data_nested_group_memberof.ldif
==============================================================================

Entry totali: 38029 Utenti: 8000 Gruppi: 30019 Altro: 10 Attributo
membri: member

Membri per gruppo (solo UTENTI diretti): count=30019 min=0 max=63
media=37.62 mediana=37 dev.std=6.15

Membri per gruppo (solo GRUPPI nidificati): count=30019 min=0 max=2
media=0.0 mediana=0 dev.std=0.03

Membri per gruppo (TOTALI, utenti+gruppi): count=30019 min=1 max=63
media=37.62 mediana=37 dev.std=6.14

Distribuzione membri per gruppo: 0-0: 0 1-5: 19 6-10: 0 11-25: 552
26-50: 28789 51-100: 659 101+: 0

Gruppi senza alcun membro: 0

Gruppi per utente (calcolato da member: sui gruppi): count=8000 min=1
max=417 media=141.17 mediana=145.0 dev.std=52.59

Distribuzione gruppi per utente: 0-0: 0 1-5: 9 6-10: 7 11-25: 40 26-50:
443 51-100: 1196 101+: 6305

Coerenza memberOf vs member: (confronto per utente, non solo per
conteggio) Utenti con memberOf presente: 8000/8000

Gruppi per utente (calcolato da memberOf dichiarato): count=8000 min=1
max=417 media=141.17 mediana=145.0 dev.std=52.59 Utenti con
DISALLINEAMENTO tra memberOf e member: 0

Utenti senza alcuna appartenenza a gruppi: 0

Annidamento gruppi: Gruppi con figli nidificati: 17 Profondita’ massima
catena: 15 Cicli rilevati: 0

Riferimenti pendenti (member: che punta a un DN inesistente nel file): 1
esempi: cn=administrators,ou=groups,dc=example,dc=com -\>
cn=admin,dc=example,dc=com

Gruppi con valori member: duplicati nella stessa entry: 0

objectClass piu’ frequenti: top 38029 groupofnames 30019 inetorgperson
8000 organizationalunit 4 applicationprocess 4 dcobject 1 organization 1
device 1 pwdpolicy 1

Attributi piu’ frequenti: objectclass 38029 structuralobjectclass 38029
entryuuid 38029 creatorsname 38029 createtimestamp 38029 entrycsn 38029
modifiersname 38029 modifytimestamp 38029 cn 38024 member 30019
description 30019 memberof 8018 uid 8000 sn 8000 userpassword 8000
pwdchangedtime 8000 ou 4 o 1 dc 1 contextcsn 1

Attributi per entry: count=38029 min=9 max=23 media=11.63 mediana=11
dev.std=1.22

Password: 8000/8000 utenti con userPassword impostata Schema di hashing:
SSHA 8000

Profondita’ del DN: count=38029 min=2 max=4 media=4.0 mediana=4
dev.std=0.01

Container (genitore del DN) piu’ popolati: 30019
ou=groups,dc=example,dc=com 8000 ou=people,dc=example,dc=com 4
dc=example,dc=com 4 ou=system,dc=example,dc=com 1 dc=com 1
ou=policies,dc=example,dc=com

Dimensione approssimata per entry (byte, somma valori attributi):
count=38029 min=288 max=23109 media=3518.69 mediana=2388 dev.std=2703.9

==============================================================================
