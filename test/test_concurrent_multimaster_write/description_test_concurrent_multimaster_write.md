# Test: Scritture Concorrenti da Più Master sotto Carico WAN

**File playbook:** `test_concurrent_multimaster_write.yml`
**Versione playbook:** 1.0
**Autore:** Elia Pinto
**Data:** 22 settembre 2026
**Data ultima esecuzione registrata:** 24 settembre 2026
**Esito ultima esecuzione:** ✅ Superato al primo tentativo (`ok=30 changed=11 unreachable=0 failed=0`)

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
  i siti, non a velocità di laboratorio.
- Controllo pre-volo esplicito (Fase 1): il test si rifiuta di partire se
  anche uno solo dei tre master non risulta già `active` su systemd,
  distinguendo un guasto residuo di un run precedente da un problema
  effettivamente causato da questo test.
- Tutte le scritture/letture di verifica passano da `ldaps://127.0.0.1:636`
  con `LDAPTLS_REQCERT=never` (certificato locale non in catena di fiducia
  del client) o da `slapcat` via SSH con utente privilegiato (`become: true`
  + porta 22), **mai `ldapsearch` di conteggio**: quest'ultimo passerebbe
  dal protocollo LDAP, con relativo `sizelimit`, e soprattutto dalla porta
  636 che la WAN simulata degrada di proposito — falsando la misura di
  convergenza.

## 3. Metodologia

### Scenario A — Scritture concorrenti su DN indipendenti

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
3. `node2` e `node3` eseguono, **in parallelo e in background**, una
   `ldapmodify` sullo stesso DN e lo stesso attributo `description`, con
   valori diversi e riconoscibili (`written-by-master-a` da `node2`,
   `written-by-master-b` da `node3`).
4. Il playbook attende il completamento di entrambe le modifiche, poi
   applica un margine fisso di 10s per lasciare propagare l'esito del
   conflitto (margine ritenuto ampio a questa scala, dato che il crash test
   correlato aveva già osservato convergenze dell'ordine di 1s su centinaia
   di entry).
5. Legge, in un'unica passata, il valore finale dell'attributo su tutti e 4
   i nodi e verifica che sia **identico ovunque** (non necessariamente quale
   dei due valori "vince": conta solo che tutti i nodi concordino sullo
   stesso esito).

### Cleanup finale (Fase 6)

Cancellazione di tutte le entry di test di entrambi gli scenari via
`ldapdelete` da `node1`, rimozione dei file temporanei su `node1`/`node2`/
`node3`, e attesa (polling reale, non fissa) della convergenza della
cancellazione a 0 record residui su tutti i 4 nodi — cluster restituito
pulito indipendentemente dall'esito del test.

## 4. Risultati ottenuti (esecuzione del 24 settembre 2026)

| Fase | Esito |
|---|---|
| Controllo pre-volo sui 3 master | ✅ Tutti `active` prima di iniziare |
| Scenario A — convergenza 400 entry combinate | ✅ **4 secondi** (`SCENARIO_A_CONVERGENCE_OK: 4s`, 400/400 record allineati sui 4 nodi, incluso il read-only) |
| Scenario B — propagazione entry condivisa pre-conflitto | ✅ Propagata su `node2`/`node3`/`node4` entro il timeout |
| Scenario B — risoluzione del conflitto | ✅ Tutti e 4 i nodi concordano sul valore `written-by-master-b` (`CONFLICT_RESOLUTION_CONSISTENT`) |
| Cleanup finale | ✅ **2 secondi** per la convergenza a 0 record residui su tutti i 4 nodi (401 entry cancellate, 0 errori `ldapdelete`) |
| Disabilitazione WAN simulata (sempre) | ✅ Eseguita |

**Play recap:** `ok=30 changed=11 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0` — nessun task fallito, nessuna assertion violata.

### Lettura dei risultati

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

## 5. Conclusioni

Il cluster N-Way Multi-Master, nella configurazione hardened attualmente in
esercizio, gestisce correttamente sia le scritture concorrenti su dati
indipendenti sia i conflitti reali sullo stesso attributo/DN provenienti da
master diversi, anche sotto le condizioni di rete degradate della WAN
simulata. Non è stato osservato alcun caso di scrittura persa, duplicata, o
di inconsistenza persistente fra i nodi (split-brain). Il test conferma,
nell'ambito dei volumi testati (200 scritture per master, 400 combinate),
l'affidabilità del meccanismo di replica sotto concorrenza reale fra master.

**Nota per estensioni future**: il file rileva esplicitamente che il numero
di scritture è stato scelto deliberatamente basso per non sovrapporre
l'effetto della concorrenza a quello, già isolato a parte, della saturazione
di un singolo provider oltre le ~1000 scritture sequenziali rapide. Un test
dedicato a verificare se la concorrenza fra master abbassi ulteriormente
quella soglia resta un'estensione possibile, ma va trattato come test a sé,
non come effetto collaterale accidentale di questo file.
