# Analisi LDIF: `../stress_test/small/create_custom_scale_data_small.ldif`

## Totali

| Metrica | Valore |
|---|---|
| Entry totali | 318 |
| Utenti | 100 |
| Gruppi | 208 |
| Altro | 10 |
| Attributo membri usato | member |

## Entry radice del suffisso

Trovata/e: 1

- **dn:** `dc=example,dc=com`
  - objectClass: top, dcObject, organization
  - contextCSN:
    - `20260908114214.604665Z#000000#001#000000`
    - `20260908114037.643048Z#000000#002#000000`
    - `20260908114038.918589Z#000000#003#000000`
  - entryUUID: `818c72ca-3fc5-1041-85b5-47247eb88a10`
  - altri attributi presenti: createtimestamp, creatorsname, dc, entrycsn, modifiersname, modifytimestamp, o, structuralobjectclass

## OID di protocollo LDAP noti trovati nei valori del file

Trovati: 0

Atteso: questi OID appartengono al protocollo LDAP (controlli, estensioni) - non ai dati della directory. Vivono nel root DSE di un server in esecuzione, non in un export statico come questo.

## Appartenenza a gruppi

**Membri per gruppo (solo UTENTI diretti)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 208 | 0 | 15 | 6.67 | 7.0 | 2.85 |

**Membri per gruppo (solo GRUPPI nidificati)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 208 | 0 | 2 | 0.04 | 0.0 | 0.24 |

**Membri per gruppo (TOTALI, utenti+gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 208 | 1 | 15 | 6.71 | 7.0 | 2.76 |

**Distribuzione membri per gruppo**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 66 |
| 6-10 | 129 |
| 11-25 | 13 |
| 26-50 | 0 |
| 51-100 | 0 |
| 101+ | 0 |

**Gruppi senza alcun membro:** 0

**Gruppi per utente (calcolato da member: sui gruppi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 100 | 3 | 29 | 13.87 | 13.5 | 5.35 |

**Distribuzione gruppi per utente**

| Fascia | Conteggio |
|---|---|
| 0-0 | 0 |
| 1-5 | 6 |
| 6-10 | 24 |
| 11-25 | 67 |
| 26-50 | 3 |
| 51-100 | 0 |
| 101+ | 0 |

## Coerenza memberOf vs member:

Confronto per utente, non solo per conteggio.

- Utenti con memberOf presente: 100/100

**Gruppi per utente (calcolato da memberOf dichiarato)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 100 | 3 | 29 | 13.87 | 13.5 | 5.35 |

**Utenti con DISALLINEAMENTO tra memberOf e member:** 0

## Utenti senza alcuna appartenenza a gruppi

Totale: 0

## Annidamento gruppi

| Metrica | Valore |
|---|---|
| Gruppi con figli nidificati | 6 |
| Profondita' massima catena | 5 |
| Cicli rilevati | 0 |

## Riferimenti pendenti

`member:` che punta a un DN inesistente nel file - totale: 1

- `cn=administrators,ou=groups,dc=example,dc=com -> cn=admin,dc=example,dc=com`

## Valori duplicati

Gruppi con valori `member:` duplicati nella stessa entry: 0

## objectClass piu' frequenti

| objectClass | Conteggio |
|---|---|
| top | 318 |
| groupofnames | 208 |
| inetorgperson | 100 |
| organizationalunit | 4 |
| applicationprocess | 4 |
| dcobject | 1 |
| organization | 1 |
| device | 1 |
| pwdpolicy | 1 |

## Attributi piu' frequenti

| Attributo | Conteggio |
|---|---|
| objectclass | 318 |
| structuralobjectclass | 318 |
| creatorsname | 318 |
| createtimestamp | 318 |
| entryuuid | 318 |
| entrycsn | 318 |
| modifiersname | 318 |
| modifytimestamp | 318 |
| cn | 313 |
| member | 208 |
| description | 208 |
| memberof | 107 |
| uid | 100 |
| sn | 100 |
| userpassword | 100 |
| pwdchangedtime | 100 |
| ou | 4 |
| o | 1 |
| dc | 1 |
| contextcsn | 1 |

**Attributi per entry**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 318 | 9 | 23 | 11.95 | 11.0 | 1.58 |

## Password

100/100 utenti con userPassword impostata

**Schema di hashing**

| Schema | Conteggio |
|---|---|
| SSHA | 100 |

**Profondita' del DN**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 318 | 2 | 4 | 3.98 | 4.0 | 0.16 |

**Container (genitore del DN) piu' popolati**

| Conteggio | Container |
|---|---|
| 208 | ou=groups,dc=example,dc=com |
| 100 | ou=people,dc=example,dc=com |
| 4 | dc=example,dc=com |
| 4 | ou=system,dc=example,dc=com |
| 1 | dc=com |
| 1 | ou=policies,dc=example,dc=com |

**Dimensione approssimata per entry (byte, somma valori attributi)**

| count | min | max | media | mediana | dev.std |
|---|---|---|---|---|---|
| 318 | 288 | 1669 | 702.45 | 651.0 | 253.94 |

