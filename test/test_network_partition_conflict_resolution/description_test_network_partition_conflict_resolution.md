# Test: Partizione di Rete (Netsplit) e Riconciliazione Deterministica dei Conflitti

**File playbook:** `test_network_partition_conflict_resolution.yml`
**Versione playbook:** 1.3
**Autore:** Elia Pinto
**Data:** 24 settembre 2026
**Data ultima esecuzione registrata:** 24 settembre 2026
**Esito ultima esecuzione:** ✅ Superato (`ok=38 changed=9 unreachable=0 failed=0`)

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
  partizione, mentre i processi non vengono mai toccati.

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
- Controllo pre-volo esplicito (Fase 1): il test si rifiuta di partire se
  anche uno solo dei tre master non risulta già `active` su systemd.
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
  link realmente caduto.
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
   non solo uno. In una mesh N-Way, un singolo leg rimasto aperto potrebbe
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
    cluster.

### Nota sulla dipendenza dagli orologi

A differenza dello Scenario B di `test_concurrent_multimaster_write.yml`
(dove i due master restano sempre raggiungibili fra loro al momento della
scrittura), qui i due CSN sono generati da nodi che per tutta la durata
della partizione non hanno modo di sincronizzarsi. Se l'ipotesi calcolata in
Fase 7 risultasse smentita in Fase 10, la causa più probabile non sarebbe
una rottura della replica ma un disallineamento fra gli orologi di sistema
dei nodi coinvolti — per questo il report include anche l'orario di sistema
letto su entrambi i lati al momento della scrittura.

## 4. Risultati ottenuti (esecuzione del 24 settembre 2026)

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

### Lettura dei risultati

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
versione qui documentata (1.3) è quella con la verifica completa, ed è
quella che ha prodotto l'esecuzione riportata in §4.
