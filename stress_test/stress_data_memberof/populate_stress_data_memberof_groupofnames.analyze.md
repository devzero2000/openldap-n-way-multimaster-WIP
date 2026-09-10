==============================================================================
ANALISI LDIF:
/home/vagrant/openldap-n-way-multimaster-WIP/stress_test/stress_data_memberof/populate_stress_data_memberof_synthetic_slapcat.ldif
==============================================================================

Entry totali: 60053 Utenti: 30002 Gruppi: 30041 Altro: 10 Attributo
membri: member

Membri per gruppo (solo UTENTI diretti): count=30041 min=0 max=10001
media=23.3 mediana=10 dev.std=364.29

Membri per gruppo (solo GRUPPI nidificati): count=30041 min=0 max=0
media=0 mediana=0 dev.std=0.0

Membri per gruppo (TOTALI, utenti+gruppi): count=30041 min=1 max=10001
media=23.3 mediana=10 dev.std=364.29

Distribuzione membri per gruppo: 0-0: 0 1-5: 1 6-10: 29999 11-25: 1
26-50: 0 51-100: 0 101+: 40

Gruppi senza alcun membro: 0

Gruppi per utente (calcolato da member: sui gruppi): count=30002 min=1
max=30 media=23.33 mediana=25.0 dev.std=6.68

Distribuzione gruppi per utente: 0-0: 0 1-5: 2 6-10: 500 11-25: 15000
26-50: 14500 51-100: 0 101+: 0

Coerenza memberOf vs member: (confronto per utente, non solo per
conteggio) Utenti con memberOf presente: 30002/30002

Gruppi per utente (calcolato da memberOf dichiarato): count=30002 min=1
max=30 media=23.33 mediana=25.0 dev.std=6.68 Utenti con DISALLINEAMENTO
tra memberOf e member: 0

Utenti senza alcuna appartenenza a gruppi: 0

Annidamento gruppi: Gruppi con figli nidificati: 0 Profondita’ massima
catena: 0 Cicli rilevati: 0

Riferimenti pendenti (member: che punta a un DN inesistente nel file): 1
esempi: cn=administrators,ou=groups,dc=example,dc=com -\>
cn=admin,dc=example,dc=com

Gruppi con valori member: duplicati nella stessa entry: 0

objectClass piu’ frequenti: top 60053 groupofnames 30041 inetorgperson
30002 organizationalunit 4 applicationprocess 4 dcobject 1 organization
1 device 1 pwdpolicy 1

Attributi piu’ frequenti: objectclass 60053 structuralobjectclass 60053
creatorsname 60053 createtimestamp 60053 entrycsn 60053 modifiersname
60053 modifytimestamp 60053 entryuuid 60053 cn 60048 member 30041
description 30040 uid 30002 sn 30002 userpassword 30002 memberof 30002
pwdchangedtime 30002 ou 4 o 1 dc 1 contextcsn 1

Attributi per entry: count=60053 min=9 max=23 media=12.5 mediana=11
dev.std=1.5

Password: 30002/30002 utenti con userPassword impostata Schema di
hashing: SSHA 30002

Profondita’ del DN: count=60053 min=2 max=4 media=4.0 mediana=4
dev.std=0.01

Container (genitore del DN) piu’ popolati: 30041
ou=groups,dc=example,dc=com 30002 ou=people,dc=example,dc=com 4
dc=example,dc=com 4 ou=system,dc=example,dc=com 1 dc=com 1
ou=policies,dc=example,dc=com

Dimensione approssimata per entry (byte, somma valori attributi):
count=60053 min=244 max=510286 media=1505.32 mediana=861
dev.std=13074.62

==============================================================================
