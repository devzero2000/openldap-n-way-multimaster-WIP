# Report di Configurazione e Tuning: Cluster OpenLDAP Multi-Master N-Way

## 1. Stato Attuale e Validazione del Cluster

Il cluster a 3 nodi (`ubuntu24lts1`, `ubuntu24lts2`, `ubuntu24lts3`) è verificato come stabile, coerente e privo di loop di replica.

L'ultimo tracciamento dei vettori di modifica attesta la corretta memorizzazione dello stato dei nodi:

* **SID 001 (Nodo 1):** `20260625083906.907148Z#000000#001#000000`
* **SID 002 (Nodo 2):** `20260625074853.939952Z#000000#002#000000`
* **SID 003 (Nodo 3):** `20260625074854.006515Z#000000#003#000000`

Il verdetto dello script di controllo incrociato ad anello (`check_ldap_syncrepl_status_nodes.sh`) restituisce uno stato ottimale su tutte le direttrici, confermando la piena consistenza e salute del cluster:

```text
[TEST 1/3] Verifica consistenza: ubuntu24lts2 <-- ubuntu24lts1...  OK - directories are in sync (W:10 - C:15)
[TEST 2/3] Verifica consistenza: ubuntu24lts3 <-- ubuntu24lts2...  OK - directories are in sync (W:10 - C:15)
[TEST 3/3] Verifica consistenza: ubuntu24lts1 <-- ubuntu24lts3...  OK - directories are in sync (W:10 - C:15)

```

---

## 2. Architettura delle Direttive di Replica (Asymmetric Topology)

Per prevenire deadlock, conflitti distruttivi e race condition, ogni nodo esegue un task di `syncrepl` puntando esplicitamente ed esclusivamente agli **altri due** nodi del cluster, escludendo se stesso tramite logica condizionale:

* **[Nodo 1: SID 001]** $\rightarrow$ Replica da: Nodo 2 (`rid=002`) e Nodo 3 (`rid=003`)
* **[Nodo 2: SID 002]** $\rightarrow$ Replica da: Nodo 1 (`rid=001`) e Nodo 3 (`rid=003`)
* **[Nodo 3: SID 003]** $\rightarrow$ Replica da: Nodo 1 (`rid=001`) e Nodo 2 (`rid=002`)

### Hardening dei Privilegi

In linea con il principio del minimo privilegio, il transito dei dati non sfrutta l'utenza root globale (`cn=admin`), bensì un account di sistema dedicato e isolato nel DIT:

* **BindDN:** `cn=nwayreplicator,ou=system,dc=example,dc=com`

---

## 3. Tuning Specifico per Reti ad Alta Latenza (WAN / Collegamenti Geografici)

In presenza di latenze elevate, fluttuazioni di banda o instabilità di rete, i parametri di runtime sono stati ottimizzati all'interno di `cn=config` per impedire disconnessioni premature e costosi reload massivi del database.

### Parametri Livello 1: Direttiva `olcSyncrepl` (Database `{1}mdb`)

* **`keepalive=240:4:15`** Preserva i socket TCP aperti attraverso i firewall. Invia un probe di controllo dopo 240 secondi di inattività, ripetendo l'invio per 4 volte ogni 15 secondi prima di considerare interrotto il canale.
* **`retry="5 10 10 30 60 120 300 +"`** Implementa un algoritmo di *exponential backoff* per i tentativi di riconnessione. Questo evita il congelamento del thread per 5 minuti (300s) al primo sbalzo di latenza, riprovando in progressione geometrica fino a stabilizzarsi a tentativi infiniti (`+`) ogni 5 minuti.
* **`timeout=15`** Innalza la tolleranza di attesa (in secondi) per il completamento delle PDU applicative di `syncrepl` prima di dichiarare il timeout del comando.

#### Esempio di stringa `olcSyncrepl` Hardened e Ottimizzata per WAN:

```text
olcSyncRepl: rid=002 provider=ldap://ubuntu24lts2.example.com bindmethod=simple binddn="cn=nwayreplicator,ou=system,dc=example,dc=com" credentials=nwayreplicator searchbase="dc=example,dc=com" type=refreshAndPersist retry="5 10 10 30 60 120 300 +" timeout=15 keepalive=240:4:15

```

### Parametri Livello 2: Timeout di Rete Globali (`cn=config`)

Configurazione per rendere il demone `slapd` tollerante sui socket lenti e congestionati:

```ldif
dn: cn=config
changetype: modify
replace: olcWriteTimeout
olcWriteTimeout: 30
-
replace: olcConnMaxPendingAuth
olcConnMaxPendingAuth: 100

```

* **`olcWriteTimeout: 30`** Attende fino a 30 secondi che un peer remoto lento legga i dati inviati sul buffer prima di abbattere forzatamente la connessione.
* **`olcConnMaxPendingAuth: 100`** Eleva a 100 il limite dei thread simultanei gestibili in fase di handshake e autenticazione, assorbendo i picchi di ritardo della WAN.

### Parametri Livello 3: Ottimizzazione I/O del Database (`olcDatabase={1}mdb`)

Sulle reti geografiche i pacchetti arrivano a burst (ondate). Al fine di massimizzare il throughput, è necessario scoppiare il tempo di scrittura su disco dai tempi sincroni di rete.

```ldif
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbNoSync
olcDbNoSync: TRUE

```

* **`olcDbNoSync: TRUE`** Disabilita il flush sincrono bloccante (`fsync`) sul disco a ogni singola transazione di replica iniettata. Delegando il flush al sistema operativo, si rimuove l'overhead di I/O e si incrementa drasticamente il throughput di sincronizzazione del cluster.


