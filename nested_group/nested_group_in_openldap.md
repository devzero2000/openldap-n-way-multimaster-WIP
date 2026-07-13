# Architettura dei Gruppi Annidati (Nested Groups): OpenLDAP vs Active
Directory

## 1. Analisi Comparativa delle Architetture

Il supporto ai gruppi annidati (*Nested Groups*) differisce radicalmente
tra Active Directory (AD) e OpenLDAP a causa della diversa filosofia con
cui i due sistemi gestiscono l'albero delle directory e il calcolo degli
attributi di appartenenza.

### Active Directory (Microsoft) * **Risoluzione Dinamica e Ricorsiva:** AD
gestisce nativamente i gruppi annidati sia in fase di scrittura che di lettura.
* **LDAP_MATCHING_RULE_IN_CHAIN:** Fornisce l'OID di estensione specifico
`1.2.840.113556.1.4.1941`. Quando un client esegue una query su un gruppo
padre utilizzando questa regola, il motore interno di AD esegue una ricerca
ricorsiva automatica lungo tutta la catena di annidamento, restituendo
istantaneamente tutti gli utenti foglia (ereditati), indipendentemente
dal livello di profondità.  * **Token Groups:** AD calcola a livello di
sicurezza il Security Identifier (SID) dell'utente espandendo dinamicamente
tutte le appartenenze dirette e indirette in un unico token di autorizzazione
al momento dell'autenticazione.

### OpenLDAP (con overlay `slapo-memberof`) * **Meccanismo Piatto
Event-Driven:** L'overlay standard `slapo-memberof` implementa un meccanismo
di manutenzione puramente referenziale guidato esclusivamente da eventi di
scrittura. Funziona rigidamente su un singolo livello (Gruppo -> Membro).
* **Comportamento in Scrittura:** Quando un oggetto (utente o sottogruppo)
viene aggiunto come valore dell'attributo `member` di un gruppo, l'overlay
intercetta l'evento e scrive l'attributo virtuale `memberOf` esclusivamente
nella entry di quel membro diretto.  * **Assenza di Ricorsione:** L'overlay
non possiede logica ricorsiva. Se il membro aggiunto è a sua volta un
gruppo contenente utenti, OpenLDAP non scende a cascata nei record degli
utenti interni per aggiornare il loro `memberOf`[cite: 5].

---

## 2. Documentazione della Batteria di Test Ansible per l'overlay memberof

Per validare empiricamente i limiti della scomposizione dei gruppi in OpenLDAP,
è stato eseguito un test strutturato tramite un apposito playbook Ansible,
per quanto riguarda l'overlay memberof. Il dataset iniettato simula uno
scenario aziendale standard di permessi gerarchici:

* **Struttura dei Dati Creata:**
  * Utente: `uid=giovanni.bianchi` (Assegnato direttamente al ruolo padre)
  * Utente: `uid=mario.rossi` (Assegnato al sottogruppo operativo) *
  Sottogruppo: `cn=Deploy-Stage1` (Contiene `uid=mario.rossi`)[cite: 6]
  * Gruppo Padre: `cn=Cloud-Architect` (Contiene `uid=giovanni.bianchi` e
  `cn=Deploy-Stage1`)[cite: 6]

### Analisi dei Risultati dei 4 Test di Conformità[cite: 6]

#### TEST 1: Estrazione utenti appartenenti
a Cloud-Architect[cite: 6] * **Filtro Query[cite: 6]:**
`(&(objectClass=inetOrgPerson)(memberOf=cn=Cloud-Architect,ou=groups,dc=example,dc=com))`[cite:
6] * **Risultato Atteso da OpenLDAP:** Viene estratto **solo**
`uid=giovanni.bianchi`[cite: 5].  * **Comportamento:** `uid=mario.rossi`
viene completamente escluso[cite: 5]. OpenLDAP esegue una ricerca lineare
sull'attributo `memberOf` e non espande il sottogruppo `cn=Deploy-Stage1`[cite:
5].

#### TEST 2: Verifica utenti appartenenti al
sottogruppo Deploy-Stage1[cite: 6] * **Filtro Query[cite: 6]:**
`(&(objectClass=inetOrgPerson)(memberOf=cn=Deploy-Stage1,ou=groups,dc=example,dc=com))`[cite:
6] * **Risultato Atteso da OpenLDAP:** Viene restituito correttamente
`uid=mario.rossi`[cite: 6].  * **Comportamento:** Essendo un'associazione
diretta a livello singolo, l'overlay ha valorizzato correttamente l'attributo
per il membro immediato.

#### TEST 3: Ispezione record completo di Mario Rossi[cite: 6] * **Filtro
Query[cite: 6]:** Base search su `uid=mario.rossi` richiedendo l'attributo
`memberOf`[cite: 6] * **Risultato Atteso da OpenLDAP:**
  ```text memberOf: cn=Deploy-Stage1,ou=groups,dc=example,dc=com
#### TEST 4: Estrazione dei membri dichiarati dentro l'oggetto Cloud-Architect

-   Filtro Query: Base search su `cn=Cloud-Architect` richiedendo l'attributo
`member`

-   Risultato Atteso da OpenLDAP

      member: uid=giovanni.bianchi,ou=People,dc=example,dc=com
        member: cn=Deploy-Stage1,ou=groups,dc=example,dc=com

## 3. Cosa aspettarsi da OpenLDAP in produzione

In presenza di architetture applicative basate su Nested Groups, l'adozione
di OpenLDAP impone precisi compromessi di cui tenere conto in fase di design:

1.  **Incompatibilità con Client "Legacy" AD-Centric:** Molti applicativi
enterprise (es. vSphere, firewall hardware, o portali che si aspettano
l'espansione automatica dei gruppi tramite query ricorsive) falliranno nel
determinare i permessi degli utenti ereditati se configurati per interrogare
OpenLDAP, poiché riceveranno solo le associazioni dirette[cite: 5].

2.  **Risoluzione a Carico del Client:** Per utilizzare i gruppi annidati
su OpenLDAP, la logica di ricorsione deve essere implementata esplicitamente
dal codice dell'applicazione client. Il client deve svolgere una prima query
per identificare i sottogruppi ed effettuare query ricorsive successive per
estrarre i DN dei membri fino a raggiungere gli utenti foglia.

3.  **L'alternativa avanzata (`slapo-dynlist` o `slapo-dds`):** Se
l'applicazione richiede tassativamente un comportamento dinamico lato
server senza poter modificare il codice client, l'overlay `slapo-memberof`
deve essere integrato o sostituito da strategie basate su URL LDAP dinamici
(`slapo-dynlist`), sebbene questo comporti un sensibile incremento del carico
computazionale sulla CPU del server OpenLDAP durante le operazioni di ricerca.
L'overlay `dynlist` permette di creare gruppi dinamici basati su una URL LDAP
(ad esempio: un gruppo che include automaticamente tutti gli utenti che hanno
`department=IT`).

-   **In lettura (Filtro membri):** Se interroghi il _gruppo_, `dynlist`
espande i membri al volo. Se configuri `dynlist` per fare valutazioni
gerarchiche, può espandere i membri dei sottogruppi quando leggi il gruppo
padre.

-   **Il grande limite (Filtro `memberOf`):** `dynlist` lavora solo in
una direzione (da Gruppo a Membri). Se un'applicazione client interroga
direttamente l'**utente** chiedendo `"A quali gruppi appartiene questo
utente?"` tramite il filtro `(memberOf=cn=GruppoPadre)`, `dynlist` non
risponde. Non genera l'attributo virtuale all'indietro sul record dell'utente.


### 4. Differenze con AD

Come abbiamo visto, Active Directory indicizza le relazioni
in modo bidirezionale e ricorsivo nativamente tramite la regola
`LDAP_MATCHING_RULE_IN_CHAIN` (`1.2.840.113556.1.4.1941`). AD sa rispondere
istantaneamente sia se chiedi i membri di un gruppo (espandendo la catena),
sia se chiedi i gruppi di un utente (risalendo la catena).

### 5. Come si potrebbe simulare AD su OpenLDAP?

Come si è prima accennato, per avvicinarsi al comportamento di AD su OpenLDAP,
la community spesso ricorre a una configurazione combinata e pesante: si
usano **`slapo-dynlist` e `slapo-memberof` insieme**, configurando `memberof`
in modo che monitori le modifiche generate dinamicamente da `dynlist`.

Tuttavia, questa soluzione presenta forti criticità in ambienti enterprise
o sotto stress test:

-   **Impatto  sulle performance:** Ogni singola ricerca richiederebbe al
server di calcolare ricorsivamente gli alberi in memoria. Con decine di
migliaia di utenti, le performance della CPU di `slapd` crollano.

-   **Fragilità nei lock del database:** Sotto carichi di scrittura massivi,
i thread che calcolano le liste dinamiche e quelli che aggiornano i referenti
di `memberof` rischiano di generare deadlock o i famosi disallineamenti di
CSN che si potrebbero  riscontrare.


### In conclusione

Se hai applicazioni client progettate strettamente per Active Directory (che
pretendono la risoluzione ricorsiva del `memberOf` o l'OID della catena),
OpenLDAP non si comporterà mai così nativamente out-of-the-box.

In produzione con OpenLDAP, la strada più sicura e performante rimane sempre
quella di gestire l'appiattimento dei gruppi a monte (es. tramite il playbook
di provisioning che mappa l'utente sia nel sottogruppo che nel gruppo padre)
oppure aggiornare la logica del client affinché esegua le query di controllo
in modo sequenziale.
