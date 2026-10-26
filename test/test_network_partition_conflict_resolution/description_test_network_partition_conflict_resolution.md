# Test: Partizione di Rete (Netsplit) e Riconciliazione Deterministica dei Conflitti

**File playbook:** `test_network_partition_conflict_resolution.yml`
**Versione playbook:** 1.5
**Autore:** Elia Pinto
**Data:** 24 settembre 2026 (ultimo aggiornamento: 26 ottobre 2026)
**Data ultima esecuzione registrata:** 26 ottobre 2026 (ambiente ubuntu 26.04, sotto WAN simulata)
**Esito ultima esecuzione:** ✅ Superato (`ok=56 changed=11 unreachable=0 failed=0`)

---

## 1. Obiettivo del test

Verificare il comportamento del cluster OpenLDAP N-Way Multi-Master sotto una
**vera partizione di rete** (netsplit) fra un master e gli altri due, a
differenza degli altri test di questa campagna:

- `test_crash_cascading_node.yml` uccide `slapd` con `kill -9` — il processo
  smette di esistere;
- la WAN simulata (MPLS+IPSec) degrada banda/latenza/perdita, ma resta
  comunque un'unica rete connessa;
- qui `slapd` resta vivo e sano su tutti i nodi: viene tagliato solo il
  traffico sulla porta di replica LDAPS (636), per il tempo della
  partizione, mentre i processi non vengono mai toccati. La partizione si
  applica sopra la WAN simulata, che resta attiva per tutto il test.

Il test copre tre proprietà distinte, verificate in sequenza:

1. **Continuità operativa**: il nodo isolato deve continuare ad accettare
   scritture in locale senza errori, come dichiarato nella Specifica
   Tecnico-Architetturale ("continuità operativa delle scritture locali
   anche in caso di isolamento... di nodi peer").
2. **Divergenza reale durante la partizione**: i due lati devono mostrare
   valori diversi mentre sono isolati — non è un difetto, è la prova che la
   partizione è davvero attiva. Senza questa verifica, un iptables
   silenziosamente inefficace farebbe "passare" il test per il motivo
   sbagliato.
3. **Riconciliazione deterministica alla guarigione**: i due `entryCSN`
   delle scritture in conflitto vengono catturati **mentre la partizione è
   ancora attiva** (per sapere con certezza quale CSN appartenga a quale
   scrittura), e usati per calcolare a priori un'ipotesi di quale valore
   "deve" vincere — il CSN lessicograficamente maggiore, dato che il
   formato CSN di OpenLDAP è interamente ordinabile come stringa (timestamp,
   contatore, serverID e mod-counter, tutti a larghezza fissa). Dopo la
   guarigione, si verifica non solo che tutti i nodi convergano allo stesso
   valore, ma che quel valore sia esattamente quello previsto dall'ipotesi —
   non un semplice "concordano", ma "concordano sul valore giusto secondo il
   CSN".

## 2. Ambiente e precondizioni

- Cluster N-Way Multi-Master su 3 nodi attivi (`node1`, `node2`, `node3`)
  più 1 nodo read-only (`node4`), identificati dalle variabili di
  inventory.
- **WAN simulata attiva per tutto il test** (dalla v1.3): la partizione si
  applica sopra la WAN, non a velocità LAN. La WAN viene accesa come primo
  passo del `block` (`simulate_wan_mpls_ipsec.yml -e stato=enabled`, con
  l'inventory del test passato via `-i`) e spenta **sempre** come primo task
  dell'`always`. In entrambi i casi lo stato reale (qdisc `netem` e regole
  mangle sulla 636) viene verificato su tutti e 4 i nodi con
  `assert_wan_state.yml`: il solo `rc=0` del playbook WAN non basta, perché
  senza il gruppo `ldap_all` nell'inventory esce con successo senza toccare
  alcun host. WAN (tabella `mangle`, marcatura + `tc`) e partizione (tabella
  `filter`, DROP su tcp/636) sono indipendenti fra loro.
- Controllo pre-volo esplicito (Fase 1): il test si rifiuta di partire se
  anche uno solo dei tre master non risulta già `active` su systemd.
- **Orologi dei nodi allineati** (Fase 1, dalla v1.4): lo scarto massimo
  fra i 4 nodi deve essere ≤ 50 ms (`test/assert_clock_skew.yml`). L'ipotesi
  sul vincitore (Fase 7) si basa sull'ordine dei CSN, che contengono l'ora
  del master che scrive: vedi la nota sugli orologi in §3.
- **La partizione è volutamente scoped alla sola porta LDAPS (636)**, l'unica
  attiva in produzione secondo `SLAPD_SERVICES="ldapi:/// ldaps:///"`),
  anziché a tutto il traffico IP fra i nodi. Motivo pratico: nell'ambiente
  di test, `ansible-playbook` gira fisicamente su `node1` stesso, che è
  anche uno dei tre master. Un DROP totale (inclusa la porta 22)
  taglierebbe fuori Ansible dal proprio canale SSH di controllo verso
  `node2`/`node3` a metà dell'applicazione della partizione, impedendo sia
  di completarla sia, più avanti, di sanarla. Limitando il blocco alla
  porta di replica, la partizione resta genuina dal punto di vista di
  syncrepl (l'unica cosa che il test vuole verificare), mentre
  SSH/management restano sempre raggiungibili dal nodo di controllo.
- Le regole `iptables` di partizione sono simmetriche su tutti e tre i nodi
  coinvolti (non solo un firewall unilaterale su `node1`), per simulare un
  link realmente caduto, e dalla v1.5 sono inserite **in testa** alle catene
  (`action: insert`): devono precedere eventuali regole ACCEPT già presenti,
  altrimenti il DROP non verrebbe mai raggiunto.
- I conteggi via `slapcat` su SSH (Fasi 2 e 11) hanno retry e restituiscono
  `-1` se la connessione fallisce, mai `0`: fino alla v1.4 una connessione
  fallita dava `0`, che in Fase 11 equivaleva a "cleanup riuscito".
- Le regole di partizione vengono rimosse **sempre**, in un blocco
  `always`, anche in caso di fallimento in una qualunque fase — un
  fallimento a metà non deve lasciare il cluster permanentemente
  partizionato.
- La creazione dell'entry di baseline è idempotente: un'eventuale entry
  residua di un run precedente interrotto (prima che la Fase 11 di cleanup
  potesse girare) viene rimossa, tollerando l'errore "non esiste", prima di
  ricreare la baseline.

## 3. Metodologia

1. **Baseline** (Fase 2): `node1` crea l'entry condivisa di test
   (`cn=netsplit-conflict-test`) con un valore iniziale. Il playbook attende
   (polling, timeout 60s) che sia propagata su tutti e 4 i nodi **prima** di
   partizionare — il conflitto deve nascere da uno stato già coerente, non
   dalla propagazione iniziale.
2. **Applica la partizione** (Fase 3): regole `iptables` simmetriche
   (`protocol: tcp`, `destination_port: 636`, `jump: DROP`) applicate sia su
   `node1` (verso `node2` e `node3`) sia specchiate su `node2`/`node3`
   (verso `node1`).
3. **Prova che la partizione è realmente attiva** (Fase 4): verifica di
   connettività TCP grezza (`/dev/tcp/.../636`) su **tutti e quattro i leg**
   rilevanti — `node2→node1`, `node3→node1`, `node1→node2`, `node1→node3` —
   non solo uno. Prima della prova, una diagnostica stampa le catene
   `INPUT`/`OUTPUT` di ogni master con i numeri di riga, per vedere dove sono
   finite le regole di partizione. In una mesh N-Way, un singolo leg rimasto aperto potrebbe
   far da ponte indiretto fra i due master isolati passando per il terzo
   nodo, invalidando silenziosamente il resto del test.
4. **Scritture in conflitto** (Fase 5): `node1` (isolato) scrive
   `description=written-during-partition-by-node1-isolated` sull'entry
   condivisa; `node2` (raggiungibile) scrive
   `description=written-during-partition-by-node2-reachable` sulla stessa
   entry/attributo. Entrambe le scritture devono avere successo (`rc=0`),
   compresa quella sul nodo isolato — è la garanzia di continuità operativa
   in oggetto al punto 1 di §1.
5. **Cattura dei CSN** (Fase 6): **mentre la partizione è ancora attiva**,
   viene letto l'`entryCSN` locale su `node1` e su `node2` via `slapcat`
   (lettura diretta su disco via SSH, non influenzata dalla partizione),
   insieme all'orario di sistema di ciascun lato.
6. **Calcolo dell'ipotesi** (Fase 7): confronto lessicografico dei due CSN
   catturati; il valore associato al CSN maggiore è il vincitore previsto
   della riconciliazione. Il risultato viene mostrato in un report **prima**
   di sanare la partizione.
7. **Verifica esplicita della divergenza** (Fase 8): lettura del valore
   attuale su tutti e 4 i nodi mentre la partizione è ancora attiva; il test
   si blocca se i due lati non divergono come atteso.
8. **Guarigione della partizione** (Fase 9): rimozione delle stesse regole
   `iptables` applicate in Fase 3, sia su `node1` sia sui suoi speculari.
9. **Convergenza e verifica dell'ipotesi** (Fase 10): attesa (polling reale,
   timeout 90s) che tutti i nodi convergano allo stesso valore, poi
   confronto esplicito fra il valore effettivamente convergito e il
   vincitore previsto in Fase 7. Il test si blocca se non coincidono
   esattamente.
10. **Cleanup finale** (Fase 11): cancellazione dell'entry di test e attesa
    (polling reale) della convergenza a 0 record residui su tutto il
    cluster. Dalla v1.5 l'esito è verificato con un `assert` (prima un
    residuo finiva comunque con `failed=0`).
11. **Chiusura garantita** (`always`): spegnimento della WAN, rimozione di
    tutte le regole di partizione su `node1`/`node2`/`node3` (`state: absent`,
    nessun effetto se già rimosse in Fase 9), verifica dello stato reale
    della WAN. Un'interruzione con Ctrl-C non esegue l'`always`: in quel caso
    rimuovere a mano partizione e WAN. Il playbook non va lanciato con
    `--check`.

### Nota sulla dipendenza dagli orologi

A differenza dello Scenario B di `test_concurrent_multimaster_write.yml`
(dove i due master restano sempre raggiungibili fra loro al momento della
scrittura), qui i due CSN sono generati da nodi che per tutta la durata
della partizione non hanno modo di sincronizzarsi. Se l'ipotesi calcolata in
Fase 7 risultasse smentita in Fase 10, la causa più probabile non sarebbe
una rottura della replica ma un disallineamento fra gli orologi di sistema
dei nodi coinvolti — per questo il report include anche l'orario di sistema
letto su entrambi i lati al momento della scrittura.

Dalla v1.4 lo sfasamento si esclude **prima** di partire, invece di
indagarlo a posteriori: il pre-volo di Fase 1 misura lo scarto fra gli
orologi dei 4 nodi e si ferma oltre 50 ms. Il 26 ottobre 2026 sulle VM 26.04
gli orologi oscillavano di ~4,5s per un conflitto fra VMware Tools e chrony,
e nello Scenario B di `test_concurrent_multimaster_write.yml` questo ha
prodotto una divergenza permanente (analisi completa nella §5 di
`description_test_concurrent_multimaster_write.md`). Qui le due scritture in
conflitto sono a ~0,5s l'una dall'altra (`node1` prima, `node2` dopo): con
secondi di scarto il vincitore poteva invertirsi rispetto all'ordine reale.

## 4. Risultati ottenuti

### 4.1 Esecuzione del 24 settembre 2026 (ambiente ubuntu 24.04, playbook v1.2, WAN non attivata dal test)

| Fase | Esito |
|---|---|
| Controllo pre-volo sui 3 master | ✅ Tutti `active` prima di iniziare |
| Baseline propagata prima della partizione | ✅ Propagata su tutti i 4 nodi entro il timeout |
| Applicazione della partizione (tcp/636, simmetrica) | ✅ Regole applicate su `node1`, `node2`, `node3` |
| Verifica di tutti e 4 i leg | ✅ Tutti e quattro bloccati (`node2→node1`, `node3→node1`, `node1→node2`, `node1→node3`) |
| Continuità operativa sul nodo isolato | ✅ Scrittura locale su `node1` riuscita (`rc=0`) nonostante l'isolamento |
| Divergenza reale durante la partizione | ✅ `node1` = valore isolato; `node2`/`node3`/`node4` = valore raggiungibile |
| Ipotesi di riconciliazione (calcolata da CSN, partizione ancora attiva) | Vincitore previsto: `written-during-partition-by-node2-reachable` |
| Convergenza dopo la guarigione | ✅ **4 secondi** (`RECONCILIATION_CONVERGED: 4s`) |
| Corrispondenza fra vincitore previsto e vincitore effettivo | ✅ **IPOTESI CONFERMATA** — coincidenza esatta |
| Cleanup finale | ✅ 0 record residui su tutti i 4 nodi |

**Play recap:** `ok=38 changed=9 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0` — nessun task fallito, nessuna assertion violata.

#### Lettura dei risultati del 24 settembre

- La partizione, scoped alla sola porta di replica LDAPS, si è dimostrata
  **completa su tutti e quattro i leg testati**: nessun percorso indiretto
  (via il terzo master) ha fatto da ponte fra i due lati isolati durante la
  finestra di test.
- Il nodo isolato (`node1`) ha continuato ad accettare scritture locali
  senza alcun errore per tutta la durata della partizione, confermando la
  garanzia di continuità operativa dichiarata per l'architettura
  Multi-Master.
- La riconciliazione, alla guarigione della partizione, non si è limitata a
  far concordare i nodi su un valore qualsiasi: il valore su cui tutto il
  cluster è convenuto è risultato **esattamente quello previsto** dal
  confronto lessicografico dei due `entryCSN`, catturati mentre la
  partizione era ancora attiva — a conferma che la risoluzione dei
  conflitti di syncrepl, anche nel caso limite di una vera interruzione di
  rete (non solo di un conflitto fra master sempre reciprocamente
  raggiungibili, già verificato in `test_concurrent_multimaster_write.yml`),
  resta deterministica e prevedibile dal formato del CSN.
- La convergenza post-guarigione (4 secondi) è dello stesso ordine di
  grandezza osservato per i conflitti "a caldo" del test di scritture
  concorrenti, nonostante qui il cluster debba riconciliare uno storico di
  modifiche accumulato durante un'interruzione di rete reale, non solo una
  sovrapposizione temporale fra scritture.

### 4.2 Esecuzione del 26 ottobre 2026 (ambiente ubuntu 26.04, playbook v1.5, sotto WAN simulata)

| Fase | Esito |
|---|---|
| WAN accesa e verificata su tutti e 4 i nodi | ✅ |
| Pre-volo sui 3 master | ✅ tutti `active` |
| Scarto fra gli orologi | ✅ 0,9 ms (soglia 50 ms) |
| Baseline propagata prima della partizione | ✅ |
| Regole di partizione | ✅ inserite in testa (righe 1–2 di `INPUT`/`OUTPUT`) su `node1`, `node2`, `node3` |
| Verifica di tutti e 4 i leg | ✅ tutti e quattro bloccati |
| Continuità operativa sul nodo isolato | ✅ scrittura locale su `node1` riuscita (`rc=0`) |
| Divergenza durante la partizione | ✅ `node1` = valore isolato; `node2`/`node3`/`node4` = valore raggiungibile |
| CSN catturati a partizione attiva | `node1`: `…114942.231274Z#…#001`, `node2`: `…114942.751329Z#…#002` (stessa ora di sistema sui due lati) |
| Vincitore previsto | `written-during-partition-by-node2-reachable` |
| Convergenza dopo la guarigione | ✅ **3 secondi** |
| Vincitore previsto = vincitore effettivo | ✅ **IPOTESI CONFERMATA** |
| Cleanup finale | ✅ 0 residui su tutti e 4 i nodi in 1s |
| WAN spenta e verificata; 0 regole di partizione residue | ✅ |

La riconciliazione resta deterministica anche sotto WAN simulata: stessi
esiti del 24 settembre, con convergenza in 3s invece di 4s.

## 5. Conclusioni

Il cluster N-Way Multi-Master gestisce correttamente non solo i conflitti
fra master sempre reciprocamente raggiungibili (già verificato altrove in
questa campagna), ma anche il caso più severo di una vera partizione di
rete: il nodo isolato mantiene piena continuità operativa in scrittura, la
divergenza durante l'isolamento è reale e osservabile, e alla guarigione la
riconciliazione converge in pochi secondi verso l'esito esatto previsto
dalla logica CSN/last-writer-wins di syncrepl — non semplicemente verso un
valore comune qualsiasi. Non è stato osservato alcun caso di split-brain
persistente, scrittura persa, o esito di riconciliazione difforme
dall'ipotesi calcolata a priori.

**Nota metodologica**: la prima stesura del playbook verificava la
partizione con un unico controllo di connettività a senso unico
(`node2→node1`). Un run reale ha mostrato una convergenza anomala durante
la finestra di isolamento (tutti i nodi, incluso quello isolato, già
allineati sul valore dell'altro lato), riconducibile a un leg della
partizione non verificato esplicitamente. Il playbook è stato quindi esteso
per verificare tutti e quattro i leg rilevanti prima di procedere — la
versione 1.2 è quella con la verifica completa e ha prodotto l'esecuzione
del 24 settembre (§4.1; le prime stesure di questo documento la indicavano
come 1.3); la 1.5 ha prodotto quella del 26 ottobre (§4.2). Fino alla 1.2 il
test non attivava la WAN: se un altro test l'aveva lasciata accesa, girava
sotto WAN senza saperlo.
