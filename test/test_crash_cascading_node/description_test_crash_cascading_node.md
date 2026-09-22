## Parte 1: Architettura e Funzionamento del Playbook

(`test_crash_cascading_node.yml`)

Il playbook ha lo scopo di misurare la resilienza, la consistenza e le
capacità di sincronizzazione delta dell'overlay `slapo-syncprov` su un
cluster OpenLDAP N-Way Multi-Master soggetto a partizionamenti di rete e
**crash non gestiti** (kill -9, non uno stop ordinato) a cascata dei nodi
consumer, con verifica di integrità dell'ambiente LMDB e misurazione della
convergenza estesa a **tutto il cluster, inclusa la replica read-only**.

*Versione documentata: 7.9. Storico completo delle versioni precedenti nel
changelog in testa al file `.yml`.*

```text
                +-----------------------------------------+
                |           Ansible Control Node           |
                +-----------------------------------------+
                                     |
               (Orchestratore via loopback locale & SSH)
                                     v
+-----------------------+   +-----------------------+   +-----------------------+
|        NODE 3         |   |        NODE 1         |   |        NODE 2         |
| ubuntu24lts3           |   | ubuntu24lts1           |   | ubuntu24lts2           |
| (Master -> Crash 2)   |   | (Write Target & MDB)   |   | (Master -> Crash 1)   |
+-----------------------+   +-----------------------+   +-----------------------+
            |                           |                           |
            +======== WAN (Netem: 50ms Latency / 0.1% Loss) ========+
                                     |
                          +-----------------------+
                          |        NODE 4          |
                          | ubuntu24lts4            |
                          | (Read-Only Replica)    |
                          +-----------------------+
```

### Flusso Logico delle Fasi

1. **Iniezione Asincrona ad Alta Frequenza (Fase 1):** Viene eseguito **uno
   script shell** (nessuna dipendenza da `python-ldap`, mai installata sul
   cluster) direttamente su `node1` (`delegate_to: "{{ node1 }}"`), avviato
   con `nohup` per sopravvivere alla chiusura della sessione SSH. Un ciclo
   genera 500 entry LDAP (`uid=crash.user.X`) con una pausa di 5ms fra
   l'una e l'altra, tutte incanalate in **una sola invocazione di
   `ldapadd -c`** — una sola connessione riusata per tutte le scritture,
   esattamente come farebbe una connessione persistente, senza bisogno di
   librerie aggiuntive. Il numero di utenti è stato deliberatamente
   ridotto da 2.000 a 500 - vedi la nota sul bug di replica isolato più
   sotto, nella Sintesi Finale, per il motivo. Prima di procedere, il
   playbook verifica che `slapd` su `node1` sia attivo fin dall'inizio
   (baseline di riferimento): il test non ha senso se il write target è
   già giù in partenza.

2. **Simulazione dei Crash a Cascata, NON gestiti (Fase 2):**
   
   * **Controllo pre-volo:** prima di toccare qualunque cosa, il playbook
     verifica che `slapd` su `node2` E `node3` sia GIÀ attivo su entrambi.
     Se uno dei due risulta già inattivo, il test si ferma immediatamente
     con un errore che lo segnala esplicitamente come uno stato residuo
     (quasi certamente un `kill -9` di un run precedente mai seguito dal
     ripristino, non un problema causato da questo run) — invece di
     proseguire su un bersaglio già compromesso e fallire più avanti in un
     modo che sembra un mistero diverso.
   * **Crash 1 (T+2s):** il PID reale di `slapd` su `node2` viene
     individuato con `pgrep -x slapd` (con retry fino a 5 tentativi, un
     secondo di pausa fra l'uno e l'altro, per assorbire un eventuale blip
     transitorio); il test si blocca se non ne trova esattamente uno (0 =
     già fermo, più di 1 = ambiguo). Il processo trovato viene poi
     terminato direttamente con `kill -9 <PID>` — un vero crash non
     gestito, non un segnale generico a `systemd`. Uno stop pulito chiude
     ordinatamente l'ambiente LMDB prima di uscire: non è un test valido
     per verificare corruzioni. Un kill -9 diretto sul processo sì.
   * Subito dopo il kill, il playbook verifica lo stato del servizio
     (`systemctl is-active` — segnala se systemd lo ha già riavviato da
     solo) ed esegue `mdb_stat -e` sull'ambiente LMDB (`lmdb-utils`
     installato come prerequisito, non bloccante) come controllo di
     integrità di base — non una verifica di corruzione approfondita, ma
     un segnale concreto se l'ambiente non è più leggibile.
   * **Crash 2 (T+6s):** stessa sequenza (pgrep con retry, blocco se non
     esattamente un processo, kill -9 diretto sul PID, verifica stato,
     `mdb_stat`) su `node3`.

3. **Attesa Completamento Scritture (Fase 3):** Il controller monitora il
   PID dello script di iniezione in `/tmp/async_load.pid` su `node1` mediante
   un ciclo `kill -0` finché tutti i record non sono stati scritti sul DB MDB.
   Al termine dell'attesa, riverifica che `slapd` su `node1` sia ANCORA
   attivo (rileva un eventuale stop avvenuto nel frattempo, anche esterno al
   playbook) prima di proseguire.

4. **Ripristino e Misurazione della Convergenza (Fase 4):** I servizi
   `slapd` su `node2` e `node3` vengono riavviati. Il playbook **verifica
   esplicitamente e in modo bloccante** che siano davvero ripartiti
   (`systemctl is-active` == `active`) — se un nodo non riparte, il test si
   ferma qui con un errore critico, segnalando una possibile corruzione da
   indagare manualmente, invece di proseguire su un nodo effettivamente giù.
   Solo a quel punto uno script shell interroga **tutti e quattro i nodi del
   cluster — `node1`, `node2`, `node3` e `node4` (read-only)** — e calcola i
   secondi esatti necessari affinché la replica Delta Sync di `syncprov`
   riallinei completamente tutti i record. L'interrogazione avviene con
   `slapcat` via SSH, non `ldapsearch`: legge direttamente dal database
   locale di ciascun nodo, bypassando del tutto il protocollo LDAP - nessun
   sizelimit da aggirare, e soprattutto nessun passaggio dalla porta 636, che
   la WAN simulata degrada apposta (SSH usa la porta 22, non toccata dallo
   shaping). Un nodo read-only rimasto indietro viene rilevato correttamente
   grazie a questo.

5. **Cleanup e Ripristino DIT (Fase 5):** Tutti i 500 utenti di test
   vengono cancellati (via `ldapsearch`+`ldapdelete`, stesso pattern degli
   script `crash_cascading_node_*_test.sh`). La verifica che la cancellazione
   sia effettivamente conversa a zero residui su tutti e quattro i nodi usa
   lo stesso meccanismo di polling via `slapcat` via SSH descritto al punto
   4 (non un'attesa fissa, e non `ldapsearch`), per le stesse ragioni.

---

## Parte 2: Discussione dei Risultati dell'Audit e del Modulo `netem`

(`simulate_wan_mpls_ipsec.yml` + `check_simulate_wan_mpls_ipsec.yml`)

L'output dell'audit conferma che la simulazione di rete WAN (MPLS + IPSec)
è attiva, corretta e conforme su **tutti e quattro i nodi del cluster**
(`ubuntu24lts1`, `ubuntu24lts2`, `ubuntu24lts3`, **e `ubuntu24lts4`, la
replica read-only**) — entrambi i playbook girano su `hosts: ldap_all`,
che nell'inventory di questo progetto comprende l'unione di `cluster` e
`readonlyreplica`. 

### 1. Validazione della Rete e di Traffic Control (`tc`)

L'audit conferma la presenza dell'infrastruttura di modellazione del traffico
a livello di Kernel Linux, **solo in egress** :

* **Qdisc Root HTB (`1:`) e Classe (`1:10`):** Il meccanismo Hierarchical
  Token Bucket è attivo per limitare e incanalare la banda.
* **Parametri `netem` applicati:**
  * **Latenza / Jitter:** Configurati a **25 ms ± 1 ms** one-way per tratta
    (RTT osservato ~50ms, essendo un link egress-only attraversato due
    volte in un round trip: andata dal client + ritorno dal server).
  * **Packet Loss:** Configurato allo **0.1%**.
* **Filtri e Marcatura Pacchetti:**
  * Le regole `iptables` nella catena `POSTROUTING` della tabella `mangle`
    contrassegnano i pacchetti TCP in uscita sulle porte **389 (LDAP)** e
    **636 (LDAPS)**, sia in `--dport` (richieste) sia in `--sport`
    (risposte — un nodo MMR è sia client che server verso i suoi pari),
    con il valore `FWMARK 10`.
  * Il filtro `tc` intercetta i pacchetti con `FWMARK 10` e li dirotta
    nella classe `1:10` dove agisce `netem`.

### 2. Analisi della Discrepanza: Ping ICMP vs. Traffico LDAP Marcato

Il test di verifica usa `tcping` (TCP-connect reale sulla porta 389, con
binding esplicito all'interfaccia) per misurare l'RTT del traffico
**davvero shaped** — un `ping` ICMP normale bypasserebbe interamente la
simulazione:

#### Perché un ping ICMP non riflette lo shaping a 25ms/tratta?

Questo comportamento è **corretto per design**:

1. **Selettività delle Regole di Mangle:** La regola `iptables` filtra
   esclusivamente il traffico TCP sulle porte `389`/`636`. I pacchetti
   ICMP non hanno un header TCP con tali porte, quindi bypassano la classe
   `1:10` e attraversano l'interfaccia senza subire il ritardo artificiale.
2. **Impatto Reale su Syncrepl / LDAPS:** Quando i nodi comunicano tra loro
   per la replica via LDAPS (`:636`), il traffico viene marcato con
   `FWMARK 10` e subisce la latenza reale configurata a ogni tratta.

---

## Parte 3: Bug di Replica Isolato Durante l'Indagine (OpenLDAP 2.6.10, standard `syncrepl`)

Durante il lavoro di validazione di questo test, un'indagine approfondita
condotta a parte (non con questo playbook, ma con script standalone
dedicati) ha isolato un problema di replica riproducibile, indipendente
dallo scenario di crash che questo file testa. Lo si documenta qui perché
è il motivo per cui il numero di utenti iniettati in Fase 1 è stato
abbassato da 2.000 a 500.

**Versione OpenLDAP coinvolta:** `2.6.10+dfsg-0ubuntu0.24.04.1` (pacchetto
Ubuntu 24.04 LTS). **Versione del playbook di deploy master in uso al
momento dell'indagine:** 1.9.1 (`deploy_multimaster_hardened_mtls_saslexternal_no_memberof_in_replica.yml`).

### Il fenomeno

Con un ritmo di scrittura sostenuto (`ldapadd -c`, decine di millisecondi
o meno fra un'entry e l'altra), superata una soglia di circa 1.000 entry
in una singola sessione di iniezione, uno o più consumer `syncrepl`
perdono silenziosamente un blocco **contiguo** di decine (fino a oltre
200, nei run più estremi) di entry - mai arrivate, non solo in ritardo.
Il fenomeno è stato osservato ripetutamente, in run diversi, con blocchi
mancanti di dimensione e posizione diverse ogni volta (es. 474-504,
1584-1604, 299-320), sempre come intervallo compatto, mai sparso.

**Soglia empirica isolata:** 500 entry convergono correttamente nella
maggior parte dei run fatti, ma non in tutti - il fenomeno si è
ripresentato anche a questo volume in run successivi (vedi "Aggiornamento"
più sotto), quindi 500 va inteso come "meno probabile", non come una
soglia sicura in senso assoluto. 1.000 entry hanno mostrato il fenomeno
più volte, nella maggioranza dei run; 2.000 e 5.000 lo mostrano
sistematicamente, con blocchi mancanti più grandi. Non è stato
identificato cosa distingua un run che converge da uno che non converge,
allo stesso volume e a parità di ogni altra condizione controllata.

### Riproduzione minima raggiunta

La forma più pulita e semplice in cui il fenomeno è stato riprodotto:

- Database completamente vuoto (redeploy pulito, nessun dataset
  preesistente)
- Un solo provider attivo (gli altri due master del mesh fermi, per
  escludere ogni interazione multi-provider)
- Un solo consumer persistente (`type=refreshAndPersist`)
- Nomi mai usati prima (prefisso univoco per timestamp, per escludere
  qualunque residuo di run precedenti)
- Nessun crash, nessun `kill -9`, nessuna simulazione WAN attiva
- 1.000 scritture pure (`ADD`), a ritmo sia di 5ms che di 50ms fra
  un'entry e l'altra (nessuna differenza fra i due ritmi)

Il fenomeno si presenta comunque.

### Cause escluse, con verifica diretta (non solo per ipotesi)

- **Crash/`kill -9`**: si riproduce identico senza alcun crash.
- **Rete/WAN simulata**: si riproduce a velocità LAN piena, con la
  simulazione disattivata; inoltre `ss -tin` sulla connessione bloccata
  ha mostrato TCP perfettamente sano (nessuna ritrasmissione, flag
  `app_limited`) - il blocco non è mai stato a livello di rete.
- **`olcThreads`**: abbassato a 4 su tutti i nodi, nessun cambiamento.
- **Timeout di connessione**, l'intera famiglia: `timeout` e
  `network-timeout` della direttiva `syncrepl` (si applicano solo a bind
  iniziale/connessione, non a una sessione già stabilita, per
  documentazione ufficiale); `olcWriteTimeout` (gia' configurato a 30s
  nel deploy, nessun effetto); `tcp-user-timeout` (esclusa a monte, la
  connessione non è mai stata bloccata a livello TCP).
- **NTP/sfasamento orologi**: differenza massima misurata fra i 4 nodi,
  in parallelo, 123ms (in gran parte imputabile al solo overhead di
  connessione SSH) - non significativa.
- **Riuso del namespace fra run**: confermato non essere la causa, dato
  che il fenomeno si riproduce anche con nomi generati apposta per non
  essere mai stati usati prima.
- **Limiti di ricerca (`olcLimits`)**: verificati `unlimited` sia per le
  identità mTLS dei consumer (per-DN) sia a livello di database frontend
  (globale) - nessun cambiamento nel fenomeno con entrambi impostati a
  `unlimited`.
- **Dimensione del dataset di base preesistente**: si riproduce
  identico anche su un database completamente vuoto.
- **Ritmo di scrittura**: 5ms e 50ms fra un'entry e l'altra mostrano lo
  stesso fenomeno, alla stessa soglia - non è una questione di velocità
  assoluta.

### Contesto dalla comunità OpenLDAP

Un thread storico della mailing list `openldap-technical` (2008-2009,
era di OpenLDAP 2.4.x) descrive lo stesso sintomo esatto: entry scartate
come "CSN too old" quando in realtà non sono mai state applicate dal
consumer, imputato a un disallineamento fra la coda dei commit e
l'aggiornamento del `contextCSN` sul provider sotto scritture
concorrenti. Un ITS più recente (#9538, aprile 2021) conferma che
`entryCSN` può non essere strettamente monotona sotto operazioni
concorrenti, anche in versioni più recenti di OpenLDAP. Nessuna fonte
trovata conferma con certezza se il problema originale del 2008 sia
stato pienamente risolto nelle versioni 2.5.x/2.6.x, o se quanto
osservato qui ne sia un residuo.

Va notato, per completezza, che un mantainer storico di OpenLDAP (Quanah
Gibson-Mount, mailing list `openldap-technical`, 24 maggio 2024) ha
raccomandato esplicitamente `syncrepl` standard (non `delta-syncrepl`)
come meccanismo più sicuro per ambienti multi-provider a partire da
OpenLDAP 2.6+ - la stessa scelta architetturale usata in questo
progetto. Questo non contraddice quanto osservato qui: la
raccomandazione riguarda la sicurezza relativa rispetto a
`delta-syncrepl` in scenari multi-provider, mentre la riproduzione più
pulita ottenuta in questa indagine è più semplice ancora (un solo
provider, un solo consumer) e non è coperta esplicitamente da
quell'affermazione.

### Aggiornamento (22/09/2026): indagine proseguita dopo run successivi

Run successivi del crash test (con `kill -9` reale, non solo scritture
pulite) hanno mostrato lo stesso fenomeno anche a 500 utenti - fino a
quel momento ritenuto un volume "sempre sicuro". Il comportamento si è
rivelato **intermittente anche a questo volume**, non deterministico.

**Prova diretta dal log del provider stesso** (non più solo dedotta dal
lato consumer): durante uno di questi run, il log di `node2` (con
`olcLogLevel: stats sync`) ha mostrato tre sessioni consumer simultanee
(`node1`, `node3`, `node4`) ricevere tutte la stessa risposta:
```
syncprov_op_search: nothing changed, finishing up initial search early
syncprov_sendinfo: refreshDelete cookie=
```
- un `refreshDelete` con cookie **vuoto**. Nello stesso momento, un
controllo diretto (`slapcat` locale, non tramite un pari) su `node2`
confermava che aveva solo 337 entry su 500 attese. `node2` dichiarava
quindi "nulla è cambiato" mentre era esso stesso incompleto - e la fase
di `REFRESH_DELETE` che ne è seguita su `node4` ha cancellato entry che
`node4` aveva correttamente ricevuto da un altro nodo, propagando
l'incompletezza di `node2` invece di limitarsi a non aggiornarsi.

**Ipotesi del `syncprov-checkpoint` testata e esclusa**: dato che il
`contextCSN` è aggiornato in memoria a ogni scrittura ma persistito su
disco solo al checkpoint configurato (`olcSpCheckpoint: 1000 10` nel
nostro deploy) o allo shutdown pulito, si è ipotizzato che uno shutdown
non pulito (`kill -9`) potesse far ripartire un nodo da un `contextCSN`
su disco stantio. Testato stringendo il checkpoint a `50 1` (venti volte
più frequente) e ripetendo il crash test più volte: **nessun
cambiamento** misurabile nel comportamento. L'ipotesi è stata quindi
esclusa come causa principale o come mitigazione praticabile.

### Stato

Il fenomeno è stato segnalato al bug tracker ufficiale di OpenLDAP (ITS):
**[bug #10604](https://bugs.openldap.org/show_bug.cgi?id=10604)**. Nel
frattempo, il numero di utenti iniettati da questo test è stato abbassato
a 500 - sotto la soglia nota - in modo che il crash test misuri quello
per cui è stato progettato (la resilienza a un `kill -9` non pulito)
senza confondersi con questo problema distinto, già isolato a parte. Va
comunque tenuto presente che anche 500 si è mostrato non sempre sicuro in
run successivi - vedi "Aggiornamento" qui sopra.

---

* **Isolamento Perfetto dell'Ambiente di Test:** La configurazione con
  `iptables` + `tc` + `netem` permette di simulare un collegamento WAN reale
  (MPLS/IPSec) limitatamente al protocollo LDAP, senza rallentare le
  sessioni SSH di gestione o gli altri servizi di sistema.

* **Performance del Cluster sotto crash NON gestito — Misurato (run del
  22/09/2026, v7.9, cluster in stato pulito, confermato dal controllo
  pre-volo, con 500 utenti - numero attuale del test, vedi Parte 3 per il
  motivo della riduzione da 2.000):**
  ✅ **Convergenza completa in 1 secondo**, su tutti e 4 i nodi (incluso il
  read-only), per i 500 record iniettati durante un crash non gestito
  (`kill -9` diretto sul processo, non uno stop ordinato) a cascata su 2
  dei 3 nodi master, sotto WAN simulata (25ms±1ms one-way, 0.1% loss).
  Nessuna corruzione rilevata su nessuno dei due nodi crashati (`mdb_stat:
  OK` in entrambi i casi) - entrambi sono ripartiti correttamente dopo il
  ripristino. Il successivo cleanup dei 500 utenti di test è riuscito al
  100% (0 errori, convergenza della cancellazione in 2 secondi, su tutti
  e 4 i nodi). `PLAY RECAP`: `ok=37 changed=8 failed=0` - run pulito al
  100%.
