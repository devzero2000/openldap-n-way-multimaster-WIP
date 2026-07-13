
```ldif dn: uid=mario.rossi,ou=People,dc=example,dc=com objectClass:
top objectClass: inetOrgPerson uid: mario.rossi cn: Mario Rossi sn: Rossi
userPassword: {SSHA}d3m0Xdfgklm12345!

```

### Descrizione

Un record utente standard strutturato con l'ObjectClass `inetOrgPerson`. Non
possiede inizialmente alcun attributo relativo ai gruppi. È la foglia
d'origine da cui si scatenerà l'effetto domino degli overlay.

---

## 2. Il Sottogruppo Operativo (Anello Statico)

```ldif dn: cn=Deploy-Stage1,ou=groups,dc=example,dc=com objectClass: top
objectClass: groupOfNames cn: Deploy-Stage1 description: Sottogruppo statico
operativo member: uid=mario.rossi,ou=People,dc=example,dc=com

```

### Descrizione

Un normale gruppo statico `groupOfNames` in cui viene associato manualmente
il DN dell'utente (`mario.rossi`).

* **L'azione di `slapo-memberof**`: Non appena questo oggetto viene scritto
sul database, l'overlay `memberof` intercetta la scrittura locale e inietta
in automatico nel record di Mario Rossi l'attributo virtuale: `memberOf:
cn=Deploy-Stage1,ou=groups,dc=example,dc=com`

---

## 3. Il Gruppo Padre (Il Motore Dinamico)

```ldif dn: cn=Cloud-Architect,ou=groups,dc=example,dc=com objectClass:
top objectClass: groupOfURLs objectClass: extensibleObject cn:
Cloud-Architect description: Gruppo dinamico padre autogroup memberURL:
ldap:///ou=People,dc=example,dc=com??sub?(memberOf=cn=Deploy-Stage1,ou=groups,dc=example,dc=com)

```

### Descrizione

Questo è il fulcro del test. Invece di elencare i membri uno a uno, si
definisce una query di ricerca dinamica tramite l'attributo `memberURL`.

* **`groupOfURLs`**: È la classe strutturale nativa che abilita l'uso delle
URL LDAP per aggregare elementi.  * **`extensibleObject`**: È la classe
ausiliaria fondamentale. Permette all'oggetto di ospitare l'attributo `member`
(strutturalmente non previsto da `groupOfURLs`) che l'overlay dovrà compilare.
* **`memberURL (La Query)`**: Dice letteralmente a OpenLDAP: *"Cerca dentro
`ou=People` tutti gli oggetti che hanno l'attributo `memberOf` uguale a
`cn=Deploy-Stage1...`"*.

---

### Il Flusso Logico di Risoluzione (Cosa succede in RAM)

1. Quando viene indicizzato `Cloud-Architect`, **`slapo-autogroup`** intercetta
il `memberURL`, esegue internamente la query e scopre che `uid=mario.rossi`
soddisfa il requisito (perché ha ottenuto quel valore al punto 2).
2. `slapo-autogroup` popola istantaneamente l'oggetto inserendo dinamicamente
in memoria la riga: `member: uid=mario.rossi,ou=People,dc=example,dc=com`
3. A questo punto, dato che la catena degli overlay vede una nuova scrittura
dell'attributo `member` dentro un gruppo, si attiva il secondo anello:
**`slapo-memberof`** legge questa modifica e aggiorna nuovamente il record
dell'utente finale, aggiungendo il secondo flag virtuale: `memberOf:
cn=Cloud-Architect,ou=groups,dc=example,dc=com`

Grazie a questa architettura, quando un applicativo interroga il cluster
cercando il gruppo principale di un utente, OpenLDAP risolve l'intera
gerarchia ad albero in soli **12-15 millisecondi**, senza che tu debba mai
gestire a mano i posizionamenti nei gruppi padre.
