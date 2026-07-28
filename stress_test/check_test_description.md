## 1. Playbook: Controllo Stato e Consistenza del Cluster OpenLDAP
(`check_cluster_healt_for_test.yml`)

### **Scopo e Ambito**

Questo playbook esegue un'**ispezione infrastrutturale locale** su ciascun
nodo del cluster, verificando la corretta configurazione del motore di
database MDB, i parametri di tuning in memoria e la presenza delle regole
di replica. Interroga direttamente la configurazione dinamica del server
(`cn=config`) via `ldapi://` sfruttando l'autenticazione SASL/EXTERNAL.

### **Fasi ed Esecuzione Step-by-Step**

1. **Verifica Indici MDB (`cn=config`):** Interroga la voce del database
MDB (`olcDatabase={1}mdb`) per estrarre la lista delle direttive
`olcDbIndex`. Serve a confermare che gli indici chiave per le query e la
sincronizzazione (`entryUUID`, `entryCSN`, `uid`, `cn`, `member`) siano
attivi e indicizzati.


2. **Verifica Parametri di Tuning (`olcSyncProvConfig`):** Ispeziona
i parametri dell'overlay `syncprov` verificando i valori attivi di
`olcSpCheckpoint` (frequenza di flush su disco del `contextCSN`) e
`olcSpSessionlog` (dimensione del buffer di memoria per i delta-sync).


3. **Verifica Architettura di Replica (`olcSyncRepl` /
`olcMultiProvider`):** Legge le direttive di replica incrociata registrate su
`olcDatabase={1}mdb,cn=config` per confermare che l'opzione `olcMultiProvider`
sia impostata su `TRUE` e che la lista dei provider `olcSyncRepl` punti
correttamente agli altri nodi del cluster.


4. **Conteggio Locale dei DN (Popolamento DIT):** Esegue un'estrazione diretta
a basso livello tramite l'utility di amministrazione `slapcat` sul database
principale (`dc=example,dc=com`) per contare il numero totale di entry (DN)
presenti fisicamente sul disco del nodo.


5. **Report di Sintesi Locale (Debugging Debug Output):** Formatta
e stampa a video una scheda di conformità distinta per ciascun host
(`ansible_facts['fqdn']`), mostrando il totale dei DN e filtrando gli output
delle ricerche LDAP per isolare indici, parametri attivi e la presenza del
tag `exattrs="memberOf"` nelle repliche.



---

## 2. Playbook: LDAP Cluster Deep Consistency Audit

### **Scopo e Ambito**

A differenza del primo script (incentrato sui parametri di configurazione del
server), questo playbook esegue un **audit strutturale e analitico sui dati
(DIT)**. Il suo obiettivo è identificare eventuali **desincronizzazioni di
dati, record orfani o mising entry** tra i vari nodi del cluster Multi-Master,
eseguendo una comparazione puntuale (*diff*) di tutti i record utente e gruppo.

### **Fasi ed Esecuzione Step-by-Step**

#### **Fase Remota sui Nodi (Esecuzione Parallela)**

1. **Staging Locale:** Crea una cartella temporanea (`/tmp/ldap_audit`)
con permessi restrittivi (`0700`) su ogni nodo del cluster.


2. **Dump e Normalizzazione Dati (Bypassing SizeLimit):** Utilizza `slapcat`
direttamente sui file di database per bypassare qualsiasi limite di risposta
applicativo (*sizelimit*). Estrae i DN di tutti gli utenti (`inetOrgPerson`)
e di tutti i gruppi (`groupOfNames`), li ordina alfabeticamente con `sort`
e li salva nei file `users_dn.txt` e `groups_dn.txt`.


3. **Conteggio Quantitativo Locale:** Calcola il numero esatto di utenti e
gruppi presenti nel dump contando le linee dei file di testo.


4. **Centralizzazione (Fetch):** Scarica i file di testo contenenti i DN
ordinati di ciascun nodo sul controller Ansible centralizzandoli nella
directory `/tmp/ldap_audit_master/<nome_nodo>/`.


5. **Pulizia Remota:** Rimuove la directory di staging `/tmp/ldap_audit`
dai nodi remoti per non lasciare residui.



#### **Fase di Elaborazione Locale (Eseguita su Ansible Controller -
`localhost`)**

6. **Assert Quantitativo di Cluster:** Confronta i conteggi numerici di
utenti e gruppi di ogni nodo rispetto al primo nodo preso come riferimento
(`groups['all'][0]`). Se un nodo ha un numero diverso di record, il task
solleva immediatamente un'allerta critica (`CRITICAL: Disallineamento
quantitativo rilevato!`).


7. **Analisi Puntuale delle Discrepanze (Diff Incrociato):** Esegue il comando
di sistema `diff -u` tra l'elenco dei DN del nodo di riferimento e l'elenco
dei DN di ciascun altro nodo del cluster.


8. **Report Finale di Consistenza Dati:** Genera una matrice completa a
video mostrando per ogni nodo target:


* Il totale degli utenti e gruppi registrati.


* Le **righe esatte del diff** che evidenziano se un utente o un gruppo
è presente su un nodo ma manca su un altro (identificando problemi di
desincronizzazione o *split-brain*).
