# Test: Scritture Concorrenti da Più Master sotto Carico WAN

**File playbook:** `test_concurrent_multimaster_write.yml`
**Versione playbook:** 1.5
**Autore:** Elia Pinto
**Data:** 22 settembre 2026 (ultimo aggiornamento: 26 ottobre 2026)
**Data ultima esecuzione registrata:** 26 ottobre 2026 (ambiente ubuntu 24.04, playbook v1.5)
**Esito ultima esecuzione:** ✅ 3 run consecutivi superati (`ok=52 changed=14 unreachable=0 failed=0`) con `systemd-timesyncd` e scarto orologi 15–46 ms — vedi §4.3 e §5

---

## 1. Obiettivo del test

Verificare il comportamento del cluster OpenLDAP N-Way Multi-Master (3 master
in scrittura + 1 nodo read-only) quando più master ricevono scritture
**simultanee**, sotto le condizioni di rete degradate della WAN simulata
(MPLS+IPSec), anziché a velocità LAN piena. Il test copre due scenari
distinti e complementari:

- **Scenario A — Scritture concorrenti su DN indipendenti**: due master
  diversi scrivono, in parallelo, entry con DN completamente distinti fra
  loro. Verifica che il throughput combinato converga correttamente su tutto
  il cluster, senza scritture perse né duplicate.
- **Scenario B — Conflitto sullo stesso DN/attributo**: due master diversi
  modificano **lo stesso attributo della stessa entry**, con valori
  differenti, in una finestra temporale sovrapposta. Verifica che la
  risoluzione del conflitto (basata su CSN, logica *last-writer-wins* di
  syncrepl) converga a un **unico valore identico su tutti e 4 i nodi**,
  senza stati divergenti persistenti (split-brain).

Il test è complementare, e volutamente distinto, dall'indagine sulla soglia
di ~1000 scritture sequenziali rapide su un singolo provider (documentata in
`description_test_crash_cascading_node.md`, Parte 3): qui il numero di
scritture è mantenuto deliberatamente basso (vedi §3) proprio per isolare il
comportamento sotto **concorrenza fra master**, senza sovrapporre un
secondo fenomeno (saturazione di un singolo provider) già isolato altrove.

## 2. Ambiente e precondizioni

- Cluster N-Way Multi-Master su 3 nodi attivi (`node1`, `node2`, `node3`) più
  1 nodo read-only (`node4`), ciascuno identificato dalle variabili di
  inventory (nessun nome host hardcoded nella logica del playbook).
- **Simulazione WAN MPLS+IPSec attiva per l'intera durata del test**
  (abilitata in `[PRE]`, disabilitata sempre in un blocco `always`, anche in
  caso di fallimento di una qualunque fase): il test misura la convergenza
  sotto la stessa banda/latenza/perdita degradate previste in produzione fra
  i siti, non a velocità di laboratorio. Dalla v1.1:
  - il playbook WAN annidato riceve l'**inventory del test** (`-i`), così la
    WAN viene accesa sul cluster giusto anche lanciando il test con `-i` su
    un altro ambiente;
  - dopo l'accensione e dopo lo spegnimento lo **stato reale** (qdisc
    `netem` e regole mangle sulla 636) viene verificato su tutti e 4 i nodi
    con `stress_test/simulate_wan_mpls_ipsec/assert_wan_state.yml`. Il solo
    `rc=0` del playbook WAN non basta: se l'inventory non contiene il gruppo
    `ldap_all` esce con successo senza toccare nessun host, e il test
    girerebbe a velocità LAN senza accorgersene;
  - lo spegnimento è il primo task dell'`always`: un host irraggiungibile in
    un task `always` interrompe i task successivi.
- Controllo pre-volo esplicito (Fase 1): il test si rifiuta di partire se
  anche uno solo dei tre master non risulta già `active` su systemd,
  distinguendo un guasto residuo di un run precedente da un problema
  effettivamente causato da questo test.
- **Orologi dei nodi allineati** (Fase 1, dalla v1.3): lo scarto massimo fra
  gli orologi dei 4 nodi deve essere ≤ `max_clock_skew_ms`, misurato con
  `test/assert_clock_skew.yml`. Dalla v1.5 la soglia non è fissa (era 50 ms)
  ma è metà di `conflict_write_gap_ms` (default 500 ms → 250 ms), l'intervallo
  esplicito fra le due scritture in conflitto dello Scenario B. È una **precondizione** dello
  Scenario B, non un dettaglio: il motivo è spiegato in §5.
- Tutte le scritture/letture di verifica passano da `ldaps://127.0.0.1:636`
  con `LDAPTLS_REQCERT=never` (certificato locale non in catena di fiducia
  del client) o da `slapcat` via SSH con utente privilegiato (`become: true`
  + porta 22), **mai `ldapsearch` di conteggio**: quest'ultimo passerebbe
  dal protocollo LDAP, con relativo `sizelimit`, e soprattutto dalla porta
  636 che la WAN simulata degrada di proposito — falsando la misura di
  convergenza.

## 3. Metodologia

### Scenario A — Scritture concorrenti su DN indipendenti

0. (dalla v1.2) Cancellazione dei residui `concurrent.*` di un run precedente
   interrotto e attesa che il conteggio sia 0 su tutti e 4 i nodi. Senza
   questo passo, dopo un run fermato in Fase 5 (la Fase 6 di cleanup non
   parte) restano 400 entry sul cluster: al run successivo `ldapadd -c`
   salterebbe in silenzio quelle già presenti e il conteggio tornerebbe
   comunque 400 = target — Scenario A passerebbe senza aver scritto nulla.
1. `node2` e `node3` avviano ciascuno, **in background** (`nohup`, PID
   tracciato su file), un'iniezione di `writes_per_node = 200` entry
   (`inetOrgPerson`) su un namespace proprio e distinto (`concurrent.a.*` da
   `node2`, `concurrent.b.*` da `node3`), con una piccola pausa (`sleep
   0.005`) fra una entry e l'altra per non generare un burst istantaneo
   irrealistico.
2. Il playbook attende (polling sul PID) il completamento di entrambe le
   iniezioni.
3. Misura, via `slapcat` su SSH e con retry, il tempo di convergenza delle
   **400 entry combinate** (200 + 200) su tutti e 4 i nodi, con timeout di
   180s e log di progresso ogni 10s in caso di attesa prolungata.

Il numero di scritture per master (200, 400 combinate) resta ben al di sotto
della soglia di ~1000 scritture isolata nell'indagine sul singolo provider,
per garantire che l'esito di questo scenario misuri esclusivamente l'effetto
della concorrenza fra master, non un effetto collaterale di saturazione.

### Scenario B — Conflitto sullo stesso DN/attributo

1. `node1` crea l'entry condivisa di test (`cn=concurrent-conflict-test`)
   con un valore iniziale dell'attributo `description`.
2. Il playbook attende (polling, timeout 60s) che l'entry sia propagata su
   `node2`, `node3` e `node4` **prima** di introdurre il conflitto — un
   controllo esplicito, non un'attesa fissa: il conflitto deve avvenire su
   uno stato già coerente, non durante la propagazione iniziale.
3. `node2` e `node3` eseguono, **in background**, una `ldapmodify` sullo
   stesso DN e lo stesso attributo `description`, con valori diversi e
   riconoscibili (`written-by-master-a` da `node2`, `written-by-master-b` da
   `node3`). Dalla v1.5 `node3` scrive almeno `conflict_write_gap_ms`
   (500 ms) dopo `node2`; prima l'intervallo era solo l'overhead di Ansible
   (vedi §5.2).
4. Il playbook attende il completamento di entrambe le modifiche, poi fa
   **polling** (timeout 60s, progresso ogni 10s) del valore dell'attributo
   su tutti e 4 i nodi via `slapcat`. Nella v1.0 c'era invece un margine
   fisso di 10s seguito da una lettura unica: sotto WAN simulata 10s non
   sono garantiti sufficienti.
5. Verifica che il valore finale sia **identico ovunque**. Il test non
   verifica *quale* dei due valori vinca, ma solo che tutti i nodi
   concordino: con orologi allineati vince la scrittura con il CSN più alto,
   cioè quella avvenuta per ultima (in pratica `written-by-master-b`, perché
   `node3` viene avviato per secondo). Se i nodi non concordano entro 60s il
   test fallisce con `CONFLICT_RESOLUTION_SPLIT_BRAIN`.

### Cleanup finale (Fase 6)

Cancellazione di tutte le entry di test di entrambi gli scenari via
`ldapdelete` da `node1`, rimozione dei file temporanei su `node1`/`node2`/
`node3`, e attesa (polling reale, non fissa) della convergenza della
cancellazione a 0 record residui su tutti i 4 nodi — cluster restituito
pulito indipendentemente dall'esito del test.

### Esito finale (Fase 7, dalla v1.4)

Tre `assert` bloccanti, **dopo** il cleanup:

- Scenario A convergente su tutti e 4 i nodi (`SCENARIO_A_CONVERGENCE_OK`);
- Scenario B coerente su tutti e 4 i nodi (`CONFLICT_RESOLUTION_CONSISTENT`);
- cancellazione conversa a 0 residui (`CLEANUP_CONVERGENCE_OK`).

Fino alla v1.3 lo Scenario A e il cleanup non avevano alcun `assert` (un
timeout finiva comunque con `failed=0`), e l'`assert` dello Scenario B stava
in Fase 5: uno split-brain fermava il test **prima** del cleanup e lasciava
le 400 entry `concurrent.*` sul cluster, come è successo il 26 ottobre (§4.2).
Ora il cluster viene ripulito comunque; i valori per nodo restano nei report
delle fasi 3, 5 e 6.

## 4. Risultati ottenuti

### 4.1 Esecuzione del 24 settembre 2026 (ambiente ubuntu 24.04, playbook v1.0)

| Fase | Esito |
|---|---|
| Controllo pre-volo sui 3 master | ✅ Tutti `active` prima di iniziare |
| Scenario A — convergenza 400 entry combinate | ✅ **4 secondi** (`SCENARIO_A_CONVERGENCE_OK: 4s`, 400/400 record allineati sui 4 nodi, incluso il read-only) |
| Scenario B — propagazione entry condivisa pre-conflitto | ✅ Propagata su `node2`/`node3`/`node4` entro il timeout |
| Scenario B — risoluzione del conflitto | ✅ Tutti e 4 i nodi concordano sul valore `written-by-master-b` (`CONFLICT_RESOLUTION_CONSISTENT`) |
| Cleanup finale | ✅ **2 secondi** per la convergenza a 0 record residui su tutti i 4 nodi (401 entry cancellate, 0 errori `ldapdelete`) |
| Disabilitazione WAN simulata (sempre) | ✅ Eseguita |

**Play recap:** `ok=30 changed=11 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0` — nessun task fallito, nessuna assertion violata.

#### Lettura dei risultati del 24 settembre

- **Scenario A**: le 400 scritture concorrenti provenienti da due master
  diversi hanno raggiunto la convergenza su tutto il cluster (3 master + 1
  read-only) in soli 4 secondi, sotto WAN simulata — nessuna entry persa né
  duplicata (400/400 = target esatto su ciascun nodo).
- **Scenario B**: il conflitto genuino sullo stesso attributo, generato da
  due master in parallelo, si è risolto in modo **deterministico e
  coerente**: tutti e 4 i nodi sono giunti allo stesso valore finale
  (`written-by-master-b`, coerente con la risoluzione CSN/last-writer-wins
  di syncrepl), senza alcuna traccia di split-brain persistente.
- Il test è passato **al primo tentativo**, senza necessità di retry o di
  interventi correttivi in corsa — a differenza di altri test di questa
  campagna (es. il crash test a cascata) che avevano richiesto più iterazioni
  di debug prima di stabilizzarsi.

### 4.2 Esecuzioni del 26 ottobre 2026 (ambiente ubuntu 26.04)

**Primo run (playbook v1.1) — ❌ fallito in Scenario B.**

| Fase | Esito |
|---|---|
| WAN accesa e verificata su tutti e 4 i nodi | ✅ |
| Scenario A — 400 entry combinate | ✅ 1 secondo |
| Scenario B — risoluzione del conflitto | ❌ dopo 60s `node1`, `node2`, `node4` = `written-by-master-a`, `node3` = `written-by-master-b` (`CONFLICT_RESOLUTION_SPLIT_BRAIN`) |
| WAN spenta e verificata (`always`) | ✅ |

Il run ha lasciato sul cluster le 400 entry `concurrent.*` (la Fase 6 non è
partita), rimosse a mano: da qui il passo 0 dello Scenario A (v1.2).
La causa del fallimento non era la replica in sé ma gli **orologi dei nodi
sfasati di secondi**: analisi completa in §5.

**Dopo la correzione degli orologi (playbook v1.3) — ✅ 6 run consecutivi
superati**, ciascuno ripartito da un cluster pulito (0 residui trovati in
apertura):

| Run | Scarto orologi | Scenario A | Scenario B | Cleanup | Play recap |
|---|---|---|---|---|---|
| 1 | 0,8 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 2s | `failed=0` |
| 2 | 1,2 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 1s | `failed=0` |
| 3 | 0,3 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 1s | `failed=0` |
| 4 | 1,2 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 1s | `failed=0` |
| 5 | 1,4 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 1s | `failed=0` |
| 6 | 0,7 ms | ✅ 1s | ✅ tutti `written-by-master-b` in 1s | ✅ 1s | `failed=0` |

In tutti i run la WAN è stata spenta e verificata (4/4 nodi) a fine test.

**Run con la v1.4 (esito verificato in Fase 7) — ✅ `ok=51 changed=14
failed=0`:** scarto orologi 0,6 ms, Scenario A 400/400 in 1s, Scenario B
`written-by-master-b` su tutti i nodi in 1s, cleanup a 0 residui in 4s, WAN
spenta e verificata. Il run è durato ~33 minuti invece di ~2 perché **tutte e
4 le VM si sono fermate insieme** durante la Fase 6 (journal vuoto su ogni
nodo fra le 12:04 e le 12:34, poi `Clock change detected` simultaneo alla
ripresa: sospensione dell'host o pausa delle VM in VMware). Il test ha
ripreso e concluso normalmente; la sincronizzazione una tantum di VMware Tools
alla ripresa, lasciata attiva apposta, ha riallineato gli orologi (scarto
0,6 ms dopo la ripresa).
I 6 run coprono circa 10 minuti: dimostrano la stabilità degli orologi nel
breve periodo, non per ore o dopo una sospensione delle VM — per questo il
controllo dello scarto resta come pre-volo a ogni esecuzione.

### 4.3 Esecuzioni del 26 ottobre 2026 (ambiente ubuntu 24.04, `systemd-timesyncd`)

**Playbook v1.4:** ✅ `failed=0`, ma con scarto orologi **42,8 ms** contro la
soglia fissa di 50 ms: sul 24.04 `systemd-timesyncd` (client SNTP, poll fino
a 34 min) tiene i nodi a decine di ms l'uno dall'altro, quindi il pre-volo
poteva fallire per uno scarto innocuo rispetto all'intervallo reale fra le
scritture in conflitto. Da qui la v1.5 (§5.2).

**Playbook v1.5 — ✅ 3 run consecutivi superati:**

| Run | Scarto orologi (soglia 250 ms) | Scenario A | Scenario B | Cleanup | Play recap |
|---|---|---|---|---|---|
| 1 | 43,0 ms | ✅ 7s | ✅ tutti `written-by-master-b` in 4s | ✅ 3s | `ok=52 failed=0` |
| 2 | 46,4 ms | ✅ 2s | ✅ tutti `written-by-master-b` in 3s | ✅ 2s | `ok=52 failed=0` |
| 3 | 15,6 ms | ✅ 4s | ✅ tutti `written-by-master-b` in 2s | ✅ 3s | `ok=52 failed=0` |

## 5. Dipendenza dagli orologi dei nodi (perché lo Scenario B può fallire)

### 5.1 Come si risolve un conflitto

Il multi-master di OpenLDAP non ha un ordinatore centrale. Ogni modifica
riceve un **CSN** (Change Sequence Number) nel formato
`AAAAMMGGhhmmss.uuuuuuZ#contatore#serverID#mod`, cioè contiene **l'orario
UTC del master che scrive**. Fra due modifiche della stessa entry vince il
CSN più alto (confronto lessicografico). L'ordine "giusto" delle scritture
è quindi definito dagli orologi dei master: per questo il multi-master
richiede orologi sincronizzati via NTP.

### 5.2 Cosa succede con orologi sfasati

Uno scarto fra i master può produrre due effetti diversi:

1. **Vince la scrittura "sbagliata", ma il cluster resta coerente.** Una
   modifica avvenuta dopo nel tempo reale perde perché il suo master ha
   l'orologio indietro. È un esito inatteso dal punto di vista del
   significato, ma tutti i nodi concordano: lo Scenario B **passa** (verifica
   la coerenza, non il vincitore).
2. **Divergenza permanente.** Succede con un intreccio preciso:
   - un master riceve da un altro master una modifica con un CSN "nel
     futuro" rispetto al proprio orologio e la applica;
   - subito dopo esegue una scrittura **locale** sulla stessa entry, e le
     assegna un CSN **più basso** di quello appena applicato;
   - lui tiene il proprio valore (per lui è l'ultima modifica arrivata);
     gli altri lo scartano come più vecchio (`CSN too old, ignoring`);
   - nessuno ripara la differenza: ciascuno risulta già aggiornato rispetto
     all'altro (il `contextCSN` di ogni nodo include già il CSN dell'altro).
     La divergenza resta finché non arriva un'altra modifica su quell'entry
     o non si fa un refresh completo.

Il caso 2 richiede uno scarto **maggiore dell'intervallo fra le due scritture
in conflitto**. Fino alla v1.4 quell'intervallo non era controllato (solo
l'overhead di Ansible fra due task, pochi decimi di secondo) e la soglia del
pre-volo era fissa a 50 ms, scollegata da esso. Dalla v1.5 il vincolo è
esplicito:

- `node3` scrive almeno `conflict_write_gap_ms` (500 ms) dopo `node2`;
- il pre-volo accetta uno scarto fino a metà di quell'intervallo (250 ms): il
  margine copre l'errore di misura e la deriva durante il test;
- un `assert` in Fase 1 blocca il test se `max_clock_skew_ms` non è minore di
  `conflict_write_gap_ms` (errore di configurazione).

Così con uno scarto in soglia il CSN di `node3` è sempre il più alto e il caso
2 non può verificarsi. 250 ms sta sopra lo scarto normale di
`systemd-timesyncd` (default su 24.04, decine di ms fra i nodi: §4.3) e molto
sotto lo sfasamento di secondi che ha rotto il test.

**È normale che il test fallisca con secondi di scarto?** Sì: il test ha
rilevato un'incoerenza **reale** del cluster, non un falso allarme. In
produzione, con lo stesso sfasamento, la stessa sequenza produrrebbe dati
diversi sui master, senza alcun errore nei log. Uno scarto di secondi fra
server sincronizzati con NTP non è però normale: è già di per sé un guasto
d'ambiente.

### 5.3 Il caso del 26 ottobre 2026: evidenze

Dal journal di slapd su `node3` (ora locale CET = UTC+1; i CSN sono in UTC):

```
11:13:08 syncrepl_entry: rid=002 LDAP_RES_SEARCH_ENTRY(LDAP_SYNC_MODIFY) csn=20261026101309.475770Z#000000#002#000000
11:13:08 syncrepl_entry: rid=002 be_modify cn=concurrent-conflict-test,... (0)
11:13:08 conn=1005 op=1 MOD dn="cn=concurrent-conflict-test,ou=People,dc=example,dc=com"
11:13:08 slap_get_csn: conn=1005 op=1 generated new csn=20261026101308.918410Z#000000#003#000000
```

1. `node3` riceve da `node2` la modifica `written-by-master-a` con CSN
   `…101309.475770Z#…#002`: secondo l'orologio di `node3` è nel futuro (le
   sue 11:13:08 < 10:13:09 UTC di `node2`). La applica.
2. Subito dopo esegue la propria `ldapmodify` (`written-by-master-b`) e le
   assegna `…101308.918410Z#…#003`, **più basso** di quello appena applicato.
3. `node1`, `node2`, `node4` scartano la modifica di `node3` come più vecchia
   e restano su `written-by-master-a`; `node3` resta su `written-by-master-b`.

Quindi l'orologio di `node2` era avanti rispetto a quello di `node3` di
**almeno 0,56s** in quel momento.

### 5.4 Causa dello sfasamento

Sulle 4 VM due servizi correggevano l'orologio verso riferimenti diversi:

| Elemento | Stato osservato |
|---|---|
| Sincronizzazione periodica di VMware Tools (`vmware-toolbox-cmd timesync status`) | `Enabled`: riallinea l'orologio della VM a quello dell'host, ~4,5s avanti rispetto all'NTP |
| chrony | attivo, sincronizza con i server NTP Ubuntu: ogni ~65s `System clock wrong by -4.5 … -5.1 seconds` |
| Frequenze stimate da chrony | 417, 1775, 749, 100028 ppm (un orologio sano sta sotto ~50 ppm) |
| Tick del kernel su `node4` | 9000 invece di 10000: orologio rallentato del 10%, mascherato dal riallineamento periodico |

Ogni VM oscillava con tempi propri, quindi in un istante qualsiasi due nodi
potevano differire di secondi.

**Correzione applicata** (26 ottobre 2026, VM 26.04):
- sincronizzazione periodica di VMware Tools disattivata
  (`vmware-toolbox-cmd timesync disable`) e, per le nuove VM, nei Vagrantfile
  (`v.vmx["tools.syncTime"] = "FALSE"`); le sincronizzazioni una tantum
  (resume/snapshot) restano attive;
- frequenza e tick del kernel azzerati (`adjtimex`), file di drift di chrony
  rimosso, chrony riavviato: disattivare VMware Tools da solo non bastava,
  gli orologi derivavano fino a -5s al minuto per le frequenze falsate;
- risultato: scarto fra i nodi stabile a 0,3–1,4 ms.

Sulle VM ubuntu 24.04 il timesync periodico di VMware Tools risulta
`Disabled` (provisioning `run: "always"` del Vagrantfile) e l'NTP resta il
default `systemd-timesyncd`, con frequenze sane (−30…+10 ppm) e tick 10000:
lo scarto residuo, decine di ms, è coperto dalla soglia della v1.5 (§4.3).
L'orologio dell'host VMware resta ~4,5s avanti rispetto all'NTP.

### 5.5 Perché il 24 settembre il test passava

Il run riuscito del 24 settembre è sull'**ambiente ubuntu 24.04** (altre VM,
altri orologi) e ha visto vincere `written-by-master-b` su tutti i nodi,
cioè l'ordine dei CSN coincideva con l'ordine reale. Con VMware Tools e
chrony in conflitto l'esito dipende dal momento:

- **lo scarto oscillava**: in certi istanti quello fra `node2` e `node3`
  era quasi zero;
- **conta il verso**: si rompe solo se il master che scrive *per secondo*
  ha l'orologio *indietro*; nel verso opposto i CSN restano ordinati e il
  test passa.

Non ci sono misure degli orologi del 24.04 di allora: è un'ipotesi coerente
con quanto osservato, non una prova. Resta comunque un problema
d'ambiente (VMware + chrony), non della logica del test.

### 5.6 Come leggere un fallimento dello Scenario B oggi

- **Fallisce il pre-volo sugli orologi** (`CLOCK_SKEW_TOO_HIGH`): problema
  d'ambiente. Controllare `chronyc tracking` su ogni nodo e che
  `vmware-toolbox-cmd timesync status` sia `Disabled`.
- **Il pre-volo passa ma lo Scenario B fallisce**: con orologi allineati è un
  **problema genuino di replica**, da indagare con il journal di slapd
  (`sync` è nel loglevel) cercando il CSN delle due modifiche su ogni nodo.
- Il pre-volo è una fotografia all'inizio del test: uno sfasamento che
  compare durante il test non viene rilevato.

## 6. Conclusioni

Il cluster N-Way Multi-Master, nella configurazione hardened attualmente in
esercizio, gestisce correttamente sia le scritture concorrenti su dati
indipendenti sia i conflitti reali sullo stesso attributo/DN provenienti da
master diversi, anche sotto le condizioni di rete degradate della WAN
simulata, **a condizione che gli orologi dei master siano sincronizzati**.
Con orologi allineati (scarto ≤ 1,4 ms, 6 run del 26 ottobre) non è stato
osservato alcun caso di scrittura persa, duplicata, o di inconsistenza
persistente fra i nodi; lo stesso vale per il run del 24 settembre, per il
quale però non ci sono misure degli orologi. Con orologi sfasati di
secondi, invece, un conflitto sullo stesso attributo può lasciare i master
**permanentemente divergenti** senza alcun errore nei log (§5): la
sincronizzazione NTP dei master è un requisito di correttezza del cluster,
non un dettaglio operativo. Il test conferma, nell'ambito dei volumi testati
(200 scritture per master, 400 combinate), l'affidabilità del meccanismo di
replica sotto concorrenza reale fra master.

**Nota per estensioni future**: il file rileva esplicitamente che il numero
di scritture è stato scelto deliberatamente basso per non sovrapporre
l'effetto della concorrenza a quello, già isolato a parte, della saturazione
di un singolo provider oltre le ~1000 scritture sequenziali rapide. Un test
dedicato a verificare se la concorrenza fra master abbassi ulteriormente
quella soglia resta un'estensione possibile, ma va trattato come test a sé,
non come effetto collaterale accidentale di questo file.
