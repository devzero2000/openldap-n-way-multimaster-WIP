# OpenLDAP N-Way Multi-Master Architecture: Under the Hood & WAN Tuning

Questo appunto tecnico analizza l'architettura **N-Way Multi-Master** in
OpenLDAP, focalizzandosi sui meccanismi interni di replica (`syncrepl` +
`syncprov`), i limiti della documentazione ufficiale e le configurazioni di
tuning necessarie per garantire stabilità e consistenza su link di rete
geografici (WAN).

## 1. Il Mito del Supporto Ufficiale vs Realtà della Documentazione

L'architettura N-Way Multi-Master (un cluster in cui tutti i nodi accettano
scritture simultanee e convergono asincronamente) **è pienamente supportata a
livello di codice nativo** in OpenLDAP (dalla versione 2.4+ e consolidata nelle
release stabili 2.5 e 2.6).

Tuttavia, la documentazione ufficiale dell'OpenLDAP Project (`Administrator's
Guide`) è storicamente scarna o quasi nulla su questo scenario specifico per
ragioni filosofiche e strutturali:

* **Manuali Ingegneristici vs Tutorial:** La guida ufficiale funge da manuale di
  riferimento delle singole direttive (es. `olcMirrorMode`), ma non offre guide
  topologiche complesse per anelli a $N$ nodi.
* **Lo Slittamento Semantico di MirrorMode:** La documentazione tratta
  diffusamente il *MirrorMode*, spesso associato erroneamente a una topologia a
  soli 2 nodi (Active-Active). Nel motore OpenLDAP, impostare `olcMirrorMode:
  TRUE` indica semplicemente al backend MDB di accettare scritture locali anche
  in presenza di direttive consumatrici `syncrepl`. Estendendo questa
  configurazione a $N$ nodi interconnessi si ottiene nativamente un cluster
  N-Way Multi-Master.

---

## 2. Architettura e Meccanismi di Consistenza

Il funzionamento del cluster si basa su tre pilastri del protocollo e del motore
MDB:

### A. ServerID (SID) Univoci

Ogni istanza nel cluster deve possedere un identificativo numerico immutabile e
distinto tramite la direttiva `olcServerID` (es. `1`, `2`, `3`). Ogni operazione
di scrittura nativa su un nodo viene marcata con il rispettivo SID.

### B. Vettori `contextCSN` Compositi

A differenza dei database relazionali tradizionali, OpenLDAP non utilizza un
singolo contatore o un orologio globale. Lo stato di consistenza del database è
definito dal `contextCSN`, una matrice interna che tiene traccia dell'ultimo
timestamp valido per **ciascun SID noto nel cluster**.

Un esempio di `contextCSN` su un cluster a 3 nodi si presenta così:

```text contextCSN: 20260625124107.044833Z#000000#001#000000 contextCSN:
20260625111245.702071Z#000000#002#000000 contextCSN:
20260625111533.462325Z#000000#003#000000

```

La sincronizzazione è considerata completata (convergenza) solo quando la copia
di questa matrice coincide al millesimo di secondo su tutti i nodi dell'anello.

### C. Risoluzione dei Conflitti (Eventual Consistency)

In caso di scritture simultanee sullo stesso oggetto (Race Condition), OpenLDAP
non va in crash. Sfrutta l'algoritmo basato sui vettori CSN per determinare
l'orario prioritario o il SID dominante. Il database converge (**Eventual
Consistency**) garantendo l'integrità strutturale del file MDB, sebbene
l'applicazione client debba essere consapevole che una delle due scritture
simultanee verrà scartata (*Last-Write-Wins*).

---

## 3. Criticità in Ambienti WAN e Best Practice di Tuning

In contesti geografici caratterizzati da latenza, packet loss o jitter, la
topologia N-Way Multi-Master genera un traffico di controllo quadratico ($N
\times (N-1)$ connessioni TCP persistenti). Se il demone `slapd` non viene
calibrato, i thread worker si saturano rapidamente portando il cluster in stallo
logico (*split-brain apparente* o *exponential backoff* della replica).

Di seguito il set di configurazioni di tuning (applicate via `cn=config`) per
stabilizzare il cluster:

### 1. Ottimizzazione del Thread Pool (`cn=config`)

Il valore stock di OpenLDAP (16 thread) è insufficiente per gestire
contemporaneamente le query dei client e i thread di sincronizzazione incrociata
in WAN.

```yaml dn: cn=config changetype: modify replace: olcThreads olcThreads: 32
-
replace: olcConnMaxPending olcConnMaxPending: 200
-
replace: olcWriteTimeout olcWriteTimeout: 10

```

* **`olcThreads`**: Innalzato a 32 per evitare il thread starvation.
* **`olcConnMaxPending`**: Limitato a 200 per evitare la saturazione della
  memoria in caso di accumulo di richieste bloccate dalla latenza di rete.
* **`olcWriteTimeout`**: Impostato a 10 secondi per forzare l'abbattimento dei
  socket TCP orfani o appesi sulla WAN.

### 2. Tuning dell'Overlay SyncProv (`olcDatabase={1}mdb,cn=config`)

```yaml dn: olcOverlay={0}syncprov,olcDatabase={1}mdb,cn=config changetype:
modify replace: olcSpSessionlog olcSpSessionlog: 5000
-
replace: olcSpCheckpoint olcSpCheckpoint: 100 10

```

* **`olcSpSessionlog`**: Mantiene in memoria RAM le ultime 5000 transazioni.
  Permette ai nodi che subiscono micro-disconnessioni WAN di riallinearsi
  istantaneamente tramite un delta parziale (**Refresh**), evitando il pesante
  ricalcolo dell'intero database (**Session Resync**).

### 3. Parametrizzazione Resiliente delle Direttive `syncrepl`

Nella definizione dei consumer `olcSyncrepl`, è tassativo abbandonare le
impostazioni stock e irrobustire i parametri di rete:

```text type=refreshAndPersist retry="5 5 10 10 30 30 60 +" timeout=30
network-timeout=15 keepalive=240:4:15

```

* **`keepalive=240:4:15`**: Invia probe a livello TCP per intercettare i
  firewall geografici che chiudono silenziosamente le connessioni inattive.
* **`retry`**: Gestisce il riallineamento progressivo senza stressare il demone
  con tentativi ossessivi in caso di blackout di rete prolungato.

---

## 4. Metodologia di Stress Test e Verifica dell'Anello

Per testare la reale salute di un cluster Multi-Master in parallelo (ad esempio
tramite automazione Ansible), **non si deve mai modificare lo stesso attributo
single-value della stessa entry contemporaneamente**. Questa pratica genera
conflitti artificiali che falsano i test.

La strategia corretta prevede scritture isolate su rami o entry separate basate
sull'hostname del nodo mittente, verificando poi in modo crociato la convergenza
globale.

### Script di Ispezione Rapida del Runtime (`cn=Monitor`)

Per verificare che il tuning dei thread sia effettivamente operativo in pancia
al demone OpenLDAP, è possibile interrogare direttamente il database di
monitoraggio interno:

```bash ldapsearch -x -H ldap://127.0.0.1:389 \ -D "cn=admin,dc=example,dc=com"
\ -w "tuapassword" \ -b "cn=Threads,cn=Monitor" +

```

L'attributo `monitoredInfo` associato a `cn=Max,cn=Threads,cn=Monitor`
confermerà l'avvenuta ricezione dei parametri di tuning (es. `monitoredInfo:
32`).

---

### Licenza & Contributi

Questo appunto è frutto di analisi d'ambiente e troubleshooting su istanze
Ubuntu 24.04 LTS. 
