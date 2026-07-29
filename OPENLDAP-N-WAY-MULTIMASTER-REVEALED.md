# OpenLDAP N-Way Multi-Master Architecture: Under the Hood & WAN Tuning

Questo appunto tecnico analizza l'architettura **N-Way Multi-Master** in
OpenLDAP, focalizzandosi sui meccanismi interni di replica (`syncrepl` +
`syncprov`), i limiti della documentazione ufficiale, la gestione del file
system e delle configurazioni OLC, e i parametri di tuning necessari per
garantire stabilità, consistenza e scalabilità su link di rete geografici
(WAN).

---

## 1. Il Mito del Supporto Ufficiale vs Realtà della Documentazione

L'architettura N-Way Multi-Master (un cluster in cui tutti i nodi accettano
scritture simultanee e convergono asincronamente) **è pienamente supportata
a livello di codice nativo** in OpenLDAP (dalla versione 2.4+ e consolidata
nelle release stabili 2.5 e 2.6).

Tuttavia, la documentazione ufficiale dell'OpenLDAP Project (`Administrator's
Guide`) è storicamente scarna o quasi nulla su questo scenario specifico
per ragioni filosofiche e strutturali:

* **Manuali Ingegneristici vs Tutorial:** La guida ufficiale funge da
manuale di riferimento delle singole direttive (es. `olcMirrorMode`),
ma non offre guide topologiche complesse per anelli a $N$ nodi.  * **Lo
Slittamento Semantico di MirrorMode:** La documentazione tratta diffusamente
il *MirrorMode*, spesso associato erroneamente a una topologia a soli 2 nodi
(Active-Active). Nel motore OpenLDAP, impostare `olcMirrorMode: TRUE` indica
semplicemente al backend MDB di accettare scritture locali anche in presenza
di direttive consumatrici `syncrepl`. Estendendo questa configurazione a $N$
nodi interconnessi si ottiene nativamente un cluster N-Way Multi-Master.

---

## 2. Architettura e Meccanismi di Consistenza

Il funzionamento del cluster si basa su tre pilastri del protocollo e del
motore MDB:

### A. ServerID (SID) Univoci

Ogni istanza nel cluster deve possedere un identificativo numerico immutabile
e distinto tramite la direttiva `olcServerID` (es. `1`, `2`, `3`). Ogni
operazione di scrittura nativa su un nodo viene marcata con il rispettivo SID.

### B. Vettori `contextCSN` Compositi

A differenza dei database relazionali tradizionali, OpenLDAP non utilizza
un singolo contatore o un orologio globale. Lo stato di consistenza del
database è definito dal `contextCSN`, una matrice interna che tiene traccia
dell'ultimo timestamp valido per **ciascun SID noto nel cluster**.

Un esempio di `contextCSN` su un cluster a 3 nodi si presenta così:

```text contextCSN: 20260728221538.851935Z#000000#001#000000
contextCSN: 20260722102615.386519Z#000000#002#000000 contextCSN:
20260722102615.848809Z#000000#003#000000

```

La sincronizzazione è considerata completata (convergenza) solo quando la
copia di questa matrice coincide su tutti i nodi dell'anello.

### C. Risoluzione dei Conflitti (Eventual Consistency)

In caso di scritture simultanee sullo stesso oggetto (Race Condition),
OpenLDAP non va in crash. Sfrutta l'algoritmo basato sui vettori CSN per
determinare l'orario prioritario o il SID dominante. Il database converge
(**Eventual Consistency**) garantendo l'integrità strutturale del file MDB,
sebbene l'applicazione client debba essere consapevole che una delle due
scritture simultanee verrà scartata (*Last-Write-Wins*).

---

## 3. Criticità in Ambienti WAN e Best Practice di Tuning per la Produzione

In contesti geografici caratterizzati da latenza, packet loss o jitter, la
topologia N-Way Multi-Master genera un traffico di controllo quadratico ($N
\times (N-1)$ connessioni TCP persistenti). Se il demone `slapd` non viene
calibrato, i thread worker si saturano rapidamente portando il cluster in
stallo logico (*split-brain apparente* o *exponential backoff* della replica).

Di seguito il set di configurazioni di tuning (applicate via `cn=config`
e nei playbook Ansible) per la produzione:

### 1. Ottimizzazione del Thread Pool e Timeout (`cn=config`)

```ldif dn: cn=config changetype: modify replace: olcThreads olcThreads: 32 -
replace: olcConnMaxPending olcConnMaxPending: 200 - replace: olcWriteTimeout
olcWriteTimeout: 30

```

* **`olcThreads`**: Innalzato a 32 per evitare il thread starvation
durante la gestione simultanea di query client e sync incrociata.  *
**`olcConnMaxPending`**: Limitato a 200 per evitare la saturazione della
memoria in caso di accumulo di richieste bloccate dalla latenza WAN.  *
**`olcWriteTimeout`**: Impostato a 30 secondi per tollerare brevi congestioni
di rete e, al contempo, forzare l'abbattimento dei socket TCP orfani o appesi
sulla WAN.

### 2. Tuning dell'Overlay SyncProv (`olcDatabase={1}mdb,cn=config`)

```ldif dn: olcOverlay={2}syncprov,olcDatabase={1}mdb,cn=config changetype:
modify replace: olcSpSessionlog olcSpSessionlog: 10000 - replace:
olcSpCheckpoint olcSpCheckpoint: 10000 10

```

* **`olcSpSessionlog`**: Mantiene in memoria RAM le ultime 10.000
transazioni. Permette ai nodi che subiscono disconnessioni temporanee di
riallinearsi istantaneamente tramite un delta parziale (**Delta Sync**),
evitando il pesante dump completo dell'intero database (**Full Re-sync**).
* **`olcSpCheckpoint`**: Forza il salvataggio su disco del `contextCSN`
aggiornato ogni 10.000 operazioni o 10 minuti, bilanciando l'I/O su disco
MDB e prevenendo la desincronizzazione in caso di blackout.

### 3. Parametrizzazione Resiliente delle Direttive `syncrepl`

```text type=refreshAndPersist retry="5 10 10 30 60 120 300 +" timeout=120
network-timeout=15 keepalive=240:4:15 exattrs="memberOf"

```

* **`timeout=120`**: Concede fino a 2 minuti per il completamento delle
risposte di replica massiva, prevenendo il blocco permanente dei thread se
la connessione degrada.  * **`network-timeout=15`**: Gestisce l'overhead
dell'handshake TLS e della latenza WAN iniziale.  * **`keepalive=240:4:15`**:
Invia probe a livello TCP per intercettare i firewall geografici che
chiudono silenziosamente le connessioni inattive.  * **`retry`**: Gestisce
il riallineamento progressivo senza stressare il demone in caso di blackout
prolungato di un nodo.

---

## 4. Architettura dei Database, File System e Segregazione OLC

Nelle versioni moderne di OpenLDAP (dalla serie 2.4+ ed in via esclusiva
nelle 2.5/2.6+), l'engine si fonda sulla netta separazione tra **dati reali
dell'albero DIT**, **configurazione dinamica in memoria** e **attributi
operativi di tracciamento**.

### A. Layout del File System e Separazione dei Ruoli

```text /etc/ldap/slapd.d/             # CONFIGURAZIONE DINAMICA (cn=config
/ OLC) ├── cn=config.ldif             # Non modificare mai a mano con
editor di testo └── cn=config/
    ├── olcDatabase={0}config.ldif └── olcDatabase={1}mdb.ldif

/var/lib/ldap/                 # DATI REALI DEL DIT (dc=example,dc=com)
├── data.mdb                   # Contiene tutte le entry, attributi
e indici └── lock.mdb                   # Gestione del memory-mapping
MVCC e concorrenza

```

1. **`back-mdb` (`/var/lib/ldap/`)**: È il motore storage primario per i
dati dell'organizzazione. Mappa i dati direttamente nella memoria virtuale
dell'OS tramite due soli file (`data.mdb` e `lock.mdb`).  2. **`back-config`
(`/etc/ldap/slapd.d/`)**: Memorizza la configurazione dell'engine su file LDIF
gestiti a caldo via LDAP (`ldapmodify`). Non va **mai modificato manualmente**
a servizio attivo per evitare la desincronizzazione dei checksum CRC interni.

### B. Gestione Immutabile di `cn=config` (Perché NON Replicare la
Configurazione)

Durante le attività di audit è possibile notare la **presenza del
`contextCSN` sul DIT dei dati (`dc=example,dc=com`) e l'assenza del
`contextCSN` sulla radice di `cn=config**`.

Questo comportamento è del tutto normale e rappresenta la Best Practice
architetturale per le infrastrutture enterprise:

* **Separazione delle Responsabilità:** La replica SyncRepl Multi-Master
è attiva **esclusivamente sui dati applicativi** (`dc=example,dc=com`),
dove le mutazioni avvengono ad alta frequenza e richiedono convergenza
automatica a caldo.  * **Prevenzione del Single Point of Failure Globale:**
Replicare a caldo l'albero `cn=config` via SyncRepl introduce il rischio
che un'errata modifica applicata su un singolo nodo (es. una regola ACL
sintatticamente errata o un modulo non caricabile) si propaghi all'istante
su tutti i nodi, compromettendo l'intero cluster contemporaneamente.  *
**Compatibilità con l'Infrastructure as Code (IaC):** La configurazione
dell'engine (`cn=config`, certificati TLS, moduli e parametri di tuning)
è gestita in modo deterministico e centralizzato tramite **playbook
Ansible**. Evitare la replica via LDAP per `cn=config` previene condizioni
di *race condition* o disallineamenti tra l'orchestratore e lo stato del
file system dei singoli server.

---

## 5. Scalabilità dell'Architettura ed Estensione a $N$ Nodi

L'architettura $N$-Way Multi-Master non pone limiti teorici rigidi nel codice
per il numero di nodi con `olcMultiProvider: TRUE`. Tuttavia, nell'ingegneria
dei sistemi LDAP esiste un limite pratico dettato dalla topologia del traffico
di rete e dal costo della consistenza.

### A. Il Limite Pratico della Topologia Full-Mesh (3-5 Nodi)

In una topologia Multi-Master pura, ogni nodo deve mantenere una sessione
di replica bidirezionale verso ciascuno degli altri $N-1$ peer. Il traffico
di sincronizzazione e lo scambio della matrice `contextCSN` crescono in modo
**quadratico** ($N \times (N-1)$):

* **3 Nodi:** 6 connessioni di replica totali (Ambiente testato e validato).
* **4 Nodi:** 12 connessioni totali.  * **5 Nodi:** 20 connessioni totali.

Il range **3–5 nodi Multi-Master** rappresenta lo *sweet spot* (punto di
equilibrio ideale) dell'infrastruttura: garantisce un'elevata tolleranza
ai guasti (il cluster sopravvive al crash di $N-1$ nodi senza perdere la
capacità di scrittura) mantenendo l'overhead di CPU e di rete a livelli
ampiamente gestibili.

### B. Scalabilità Oltre i 5 Nodi: Modello Ibrido (Hub-and-Spoke)

Se l'organizzazione richiede di estendere i servizi LDAP a decine di data
center o sedi periferiche, non si aggiungono ulteriori nodi Multi-Master
alla mesh primario, ma si adotta la topologia **Hub-and-Spoke**:

```text
               +----------------------------------+ |       CORE
               MULTI-MASTER (HUB)    | |  (3 Nodi Active-Active Scrittura)
               | +----------------------------------+
                 /              |               \
                /               |                \
               v                v                 v
     +-----------------+ +-----------------+ +-----------------+ |
     Read-Only Node  | | Read-Only Node  | | Read-Only Node  | | (Sede
     Perif. A) | | (Sede Perif. B) | | (Sede Perif. C) | +-----------------+
     +-----------------+ +-----------------+

```

1. **Core Multi-Master (Hub - 3 Nodi):** Gestisce centralmente l'integrità
del database ed accetta tutte le operazioni di scrittura dell'organizzazione.
2. **Edge Consumer (Spoke - Read-Only):** Nodi periferici posizionati nei
singoli Data Center/Branch che eseguono SyncRepl unidirezionale attingendo
da uno dei Master del Core.  3. **Write Referral (`slapo-chain`):**
Eventuali scritture inviate casualmente ai nodi periferici Read-Only vengono
trasparentemente reindirizzate (via Referral/Chaining) al Core Multi-Master.

---

## 6. Metodologia di Stress Test e Verifica dell'Anello

Per testare la reale salute di un cluster Multi-Master in parallelo (ad esempio
tramite automazione Ansible), **non si deve mai modificare lo stesso attributo
single-value della stessa entry contemporaneamente**. Questa pratica genera
conflitti artificiali che falsano i test.

La strategia corretta prevede scritture isolate su rami o entry separate
basate sull'hostname del nodo mittente, verificando poi in modo crociato la
convergenza globale.

### Script di Ispezione Rapida del Runtime (`cn=Monitor`)

Per verificare che il tuning dei thread sia effettivamente operativo in
pancia al demone OpenLDAP, è possibile interrogare direttamente il database
di monitoraggio interno:

```bash ldapsearch -x -H ldap://127.0.0.1:389 \
  -D "cn=admin,dc=example,dc=com" \ -w "tuapassword" \ -b
  "cn=Threads,cn=Monitor" +

```

L'attributo `monitoredInfo` associato a `cn=Max,cn=Threads,cn=Monitor`
confermerà l'avvenuta ricezione dei parametri di tuning (es. `monitoredInfo:
32`).

---

### Licenza & Contributi

Questo appunto è frutto di analisi d'ambiente, stress test e troubleshooting
su istanze Ubuntu 24.04 LTS.
