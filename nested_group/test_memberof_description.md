Il playbook Ansible (`test_slapo_memberof.yml`) è uno **script di test
funzionale e validazione di conformità** progettato per verificare il
corretto funzionamento dell'overlay **`slapo-memberof`** in un ambiente
OpenLDAP (inclusa la validazione della replica tra i nodi del cluster).

---

### Architettura e Logica Operativa

Il playbook è strutturato per gestire il ciclo di vita completo del test
(creazione dati, replica, verifica, eventuale pulizia) in base alla variabile
`stato` (che di default è impostata a `"start"`):

#### 1. FASE DI PULIZIA (`stato: "stop"`)

Se eseguito con `stato: "stop"`, il playbook rimuove in ordine sequenziale gli
oggetti foglia (gli utenti e i gruppi creati per il test) e successivamente
cancella le Unità Organizzative (`ou=People` e `ou=groups`).

* **Controllo della conconrenza:** Per evitare conflitti di replica, la
cancellazione viene eseguita **esclusivamente dal primo nodo coordinatore**
(`groups['cluster'][0]`).



#### 2. PREPARAZIONE DEL DIT (`stato: "start"`)

Sempre ed esclusivamente dal **nodo coordinatore**:

* Crea la struttura base delle Unità Organizzative: **`ou=People`**
e **`ou=groups`**.



#### 3. POPOLAMENTO DATASET DI PROVA (`stato: "start"`)

Crea un piccolo dataset di controllo rappresentativo per testare l'associazione
tra gruppi e utenti:

* **Utenti (`inetOrgPerson`):** * `mario.rossi`

* `giovanni.bianchi`



* **Gruppi (`groupOfNames`):** * `Deploy-Stage1`: contiene come membro solo
`mario.rossi` (`member: uid=mario.rossi,...`).


* `Cloud-Architect`: contiene come membri sia `mario.rossi` sia
`giovanni.bianchi`.




* **Pausa Syncrepl:** Inserisce una pausa di **2 secondi** per consentire
al motore Syncrepl di replicare le nuove entry e permettere all'overlay
`slapo-memberof` di calcolare/iniettare localmente l'attributo inverso sui
vari nodi.



#### 4. BATTERIA DI VERIFICA (Eseguita in parallelo su TUTTI i nodi del
cluster)

Mentre la creazione dei dati avviene solo sul primo nodo, **la fase di test
viene eseguita contemporaneamente su ogni singolo nodo del cluster** per
accertarsi che `slapd-memberof` funzioni ed esponga l'attributo `memberOf`
dappertutto:

1. **TEST 1 (Ricerca inversa con filtro):** Interroga l'albero
`ou=People` cercando tutti gli utenti che hanno l'attributo
`memberOf=cn=Cloud-Architect,ou=groups,...`. Deve restituire sia Mario Rossi
che Giovanni Bianchi.


2. **TEST 2 (Query BASE su Mario Rossi):** Esegue una lettura diretta (scope
`base`) sulla voce di Mario Rossi chiedendo esplicitamente l'attributo
operativo `memberOf`. Deve restituire **due** valori (entrambi i gruppi).


3. **TEST 3 (Query BASE su Giovanni Bianchi):** Esegue una lettura
diretta sul record di Giovanni Bianchi. Deve restituire **un solo** valore
(`Cloud-Architect`).



#### 5. REPORT E AUDITING

Nell'ultimo task, Ansible stampa a schermo tramite il modulo `debug`
l'output dei tre comandi `ldapsearch` ricevuti da ciascun nodo, permettendo
di confermare visualmente che:

* L'overlay `slapo-memberof` stia generando correttamente l'attributo
operativo.


* La replica dei dati sui nodi sia convergente e consistente.
