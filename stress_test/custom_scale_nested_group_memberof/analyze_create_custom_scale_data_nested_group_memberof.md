# Analisi LDIF: `../stress_test/custom_scale_nested_group_memberof/create_custom_scale_data_nested_group_memberof.ldif`

## Totali

| Metrica | Valore |
|---|---|
| Entry totali | 38029 |
| Utenti | 8000 |
| Gruppi | 30019 |
| Altro | 10 |
| Attributo membri usato | member |

## Entry radice del suffisso

Trovata/e: 1

- **dn:** `dc=example,dc=com`
  - objectClass: top, dcObject, organization
  - contextCSN:
    - `20260910091319.905284Z#000000#001#000000`
    - `20260828080046.051895Z#000000#002#000000`
    - `20260828075710.363276Z#000000#003#000000`
  - entryUUID: `05009f2a-3687-1041-9b91-5f6eb52f279c`
  - altri attributi presenti: createtimestamp, creatorsname, dc, entrycsn, modifiersname, modifytimestamp, o, structuralobjectclass

## OID di protocollo LDAP noti trovati nei valori del file

Trovati: 0

Atteso: questi OID appartengono al protocollo LDAP (controlli, estensioni) - non ai dati della directory. Vivono nel root DSE di un server in esecuzione, non in un export statico come questo.

## Appartenenza a gruppi

**Membri per gruppo (solo UTENTI diretti)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30019 | 0 | 63 | 37.62 | 37 | 6.15 |

**Membri per gruppo (solo GRUPPI nidificati)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30019 | 0 | 2 | 0.0 | 0 | 0.03 |

**Membri per gruppo (TOTALI, utenti+gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 30019 | 1 | 63 | 37.62 | 37 | 6.14 |

**Distribuzione membri per gruppo**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 19 |
| 6-10 | 0 |
| 11-25 | 552 |
| 26-50 | 28789 |
| 51-100 | 659 |
| 101+ | 0 |

**Gruppi senza alcun membro:** 0

**Gruppi per utente (calcolato da member: sui gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 8000 | 1 | 417 | 141.17 | 145.0 | 52.59 |

**Distribuzione gruppi per utente**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 9 |
| 6-10 | 7 |
| 11-25 | 40 |
| 26-50 | 443 |
| 51-100 | 1196 |
| 101+ | 6305 |

## Coerenza memberOf vs member:

Confronto per utente, non solo per conteggio.

- Utenti con memberOf presente: 8000/8000

**Gruppi per utente (calcolato da memberOf dichiarato)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 8000 | 1 | 417 | 141.17 | 145.0 | 52.59 |

**Utenti con DISALLINEAMENTO tra memberOf e member:** 0

## Utenti senza alcuna appartenenza a gruppi

Totale: 0

## Annidamento gruppi

| Metrica | Valore |
|---|---|
| Gruppi con figli nidificati | 17 |
| Profondita' massima catena | 15 |
| Cicli rilevati | 0 |

## Riferimenti pendenti

`member:` che punta a un DN inesistente nel file - totale: 1

- `cn=administrators,ou=groups,dc=example,dc=com -> cn=admin,dc=example,dc=com`

## Valori duplicati

Gruppi con valori `member:` duplicati nella stessa entry: 0

## objectClass piu' frequenti

| objectClass | Conteggio |
|---|---|
| top | 38029 |
| groupofnames | 30019 |
| inetorgperson | 8000 |
| organizationalunit | 4 |
| applicationprocess | 4 |
| dcobject | 1 |
| organization | 1 |
| device | 1 |
| pwdpolicy | 1 |

## Attributi piu' frequenti

| Attributo | Conteggio |
|---|---|
| objectclass | 38029 |
| structuralobjectclass | 38029 |
| entryuuid | 38029 |
| creatorsname | 38029 |
| createtimestamp | 38029 |
| entrycsn | 38029 |
| modifiersname | 38029 |
| modifytimestamp | 38029 |
| cn | 38024 |
| member | 30019 |
| description | 30019 |
| memberof | 8018 |
| uid | 8000 |
| sn | 8000 |
| userpassword | 8000 |
| pwdchangedtime | 8000 |
| ou | 4 |
| o | 1 |
| dc | 1 |
| contextcsn | 1 |

**Attributi per entry**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 38029 | 9 | 23 | 11.63 | 11 | 1.22 |

## Password

8000/8000 utenti con userPassword impostata

**Schema di hashing**

| Schema | Conteggio |
|---|---|
| SSHA | 8000 |

**Profondita' del DN**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 38029 | 2 | 4 | 4.0 | 4 | 0.01 |

**Container (genitore del DN) piu' popolati**

| Conteggio | Container |
|---|---|
| 30019 | ou=groups,dc=example,dc=com |
| 8000 | ou=people,dc=example,dc=com |
| 4 | dc=example,dc=com |
| 4 | ou=system,dc=example,dc=com |
| 1 | dc=com |
| 1 | ou=policies,dc=example,dc=com |

**Dimensione approssimata per entry (byte, somma valori attributi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 38029 | 288 | 23109 | 3518.69 | 2388 | 2703.9 |

