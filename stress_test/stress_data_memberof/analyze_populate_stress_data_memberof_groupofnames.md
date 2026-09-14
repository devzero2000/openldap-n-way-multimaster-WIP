# Analisi LDIF: `../stress_test/stress_data_memberof/populate_stress_data_memberof_groupofnames.ldif`

## Totali

| Metrica | Valore |
|---|---|
| Entry totali | 60053 |
| Utenti | 30002 |
| Gruppi | 30041 |
| Altro | 10 |
| Attributo membri usato | member |

## Entry radice del suffisso

Trovata/e: 1

- **dn:** `dc=example,dc=com`
  - objectClass: top, dcObject, organization
  - contextCSN:
    - `20260910090000.021000Z#000000#001#000000`
    - `20260910090000.028000Z#000000#002#000000`
    - `20260910090000.035000Z#000000#003#000000`
  - entryUUID: `b6d11d92-589e-4a13-80e8-cb9b25a9915b`
  - altri attributi presenti: createtimestamp, creatorsname, dc, entrycsn, modifiersname, modifytimestamp, o, structuralobjectclass

## OID di protocollo LDAP noti trovati nei valori del file

Trovati: 0

Atteso: questi OID appartengono al protocollo LDAP (controlli, estensioni) - non ai dati della directory. Vivono nel root DSE di un server in esecuzione, non in un export statico come questo.

## Appartenenza a gruppi

**Membri per gruppo (solo UTENTI diretti)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30041 | 0 | 10001 | 23.3 | 10 | 364.29 |

**Membri per gruppo (solo GRUPPI nidificati)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30041 | 0 | 0 | 0 | 0 | 0.0 |

**Membri per gruppo (TOTALI, utenti+gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30041 | 1 | 10001 | 23.3 | 10 | 364.29 |

**Distribuzione membri per gruppo**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 1 |
| 6-10 | 29999 |
| 11-25 | 1 |
| 26-50 | 0 |
| 51-100 | 0 |
| 101+ | 40 |

**Gruppi senza alcun membro:** 0

**Gruppi per utente (calcolato da member: sui gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30002 | 1 | 30 | 23.33 | 25.0 | 6.68 |

**Distribuzione gruppi per utente**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 2 |
| 6-10 | 500 |
| 11-25 | 15000 |
| 26-50 | 14500 |
| 51-100 | 0 |
| 101+ | 0 |

## Coerenza memberOf vs member:

Confronto per utente, non solo per conteggio.

- Utenti con memberOf presente: 30002/30002

**Gruppi per utente (calcolato da memberOf dichiarato)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30002 | 1 | 30 | 23.33 | 25.0 | 6.68 |

**Utenti con DISALLINEAMENTO tra memberOf e member:** 0

## Utenti senza alcuna appartenenza a gruppi

Totale: 0

## Annidamento gruppi

| Metrica | Valore |
|---|---|
| Gruppi con figli nidificati | 0 |
| Profondita' massima catena | 0 |
| Cicli rilevati | 0 |

## Riferimenti pendenti

`member:` che punta a un DN inesistente nel file - totale: 1

- `cn=administrators,ou=groups,dc=example,dc=com -> cn=admin,dc=example,dc=com`

## Valori duplicati

Gruppi con valori `member:` duplicati nella stessa entry: 0

## objectClass piu' frequenti

| objectClass | Conteggio |
|---|---|
| top | 60053 |
| groupofnames | 30041 |
| inetorgperson | 30002 |
| organizationalunit | 4 |
| applicationprocess | 4 |
| dcobject | 1 |
| organization | 1 |
| device | 1 |
| pwdpolicy | 1 |

## Attributi piu' frequenti

| Attributo | Conteggio |
|---|---|
| objectclass | 60053 |
| structuralobjectclass | 60053 |
| creatorsname | 60053 |
| createtimestamp | 60053 |
| entrycsn | 60053 |
| modifiersname | 60053 |
| modifytimestamp | 60053 |
| entryuuid | 60053 |
| cn | 60048 |
| member | 30041 |
| description | 30040 |
| uid | 30002 |
| sn | 30002 |
| userpassword | 30002 |
| memberof | 30002 |
| pwdchangedtime | 30002 |
| ou | 4 |
| o | 1 |
| dc | 1 |
| contextcsn | 1 |

**Attributi per entry**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 60053 | 9 | 23 | 12.5 | 11 | 1.5 |

## Password

30002/30002 utenti con userPassword impostata

**Schema di hashing**

| Schema | Conteggio |
|---|---|
| SSHA | 30002 |

**Profondita' del DN**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 60053 | 2 | 4 | 4.0 | 4 | 0.01 |

**Container (genitore del DN) piu' popolati**

| Conteggio | Container |
|---|---|
| 30041 | ou=groups,dc=example,dc=com |
| 30002 | ou=people,dc=example,dc=com |
| 4 | dc=example,dc=com |
| 4 | ou=system,dc=example,dc=com |
| 1 | dc=com |
| 1 | ou=policies,dc=example,dc=com |

**Dimensione approssimata per entry (byte, somma valori attributi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 60053 | 244 | 510286 | 1505.32 | 861 | 13074.62 |

