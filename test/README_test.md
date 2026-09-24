# Test del cluster OpenLDAP N-Way Multi-Master

Nota descrittiva dei playbook di test presenti in questa directory: nome,
scenario simulato, e cosa ciascuno verifica.

---

## `test_crash_cascading_node.yml`

**Scenario simulato:** crash di processo (`kill -9`) su uno o più nodi del
cluster — a differenza degli altri due test, qui `slapd` smette proprio di
esistere, non semplicemente di essere raggiungibile.

**Cosa verifica:** la capacità del cluster di sopravvivere alla perdita
improvvisa di un master (e di master in cascata), il corretto riavvio e
riallineamento del nodo quando torna attivo, e — nella parte dedicata alla
saturazione — l'esistenza di una soglia (circa 1000 scritture sequenziali
rapide su un singolo provider) oltre la quale il comportamento del nodo
sotto carico va investigato a parte.

---

## `test_concurrent_multimaster_write.yml`

**Scenario simulato:** scritture concorrenti da più master, sotto le
condizioni di rete degradate della WAN simulata (MPLS+IPSec) — banda,
latenza e perdita ridotte, ma un'unica rete sempre connessa; nessun nodo
viene isolato o terminato.

**Cosa verifica:** due proprietà distinte. (1) Che scritture concorrenti su
DN indipendenti, provenienti da master diversi, convergano su tutto il
cluster senza perdite né duplicazioni. (2) Che un conflitto genuino sullo
stesso DN/attributo, scritto in parallelo da due master diversi, si risolva
in modo deterministico verso un unico valore identico su tutti i nodi
(risoluzione CSN/last-writer-wins di syncrepl), senza split-brain.

*Descrizione dettagliata:* `description_test_concurrent_multimaster_write.md`

---

## `test_network_partition_conflict_resolution.yml`

**Scenario simulato:** una vera partizione di rete (netsplit) fra un master
e gli altri due — a differenza del crash test, `slapd` resta vivo e sano su
tutti i nodi; viene tagliato solo il traffico sulla porta di replica LDAPS
(636) fra i lati della partizione, per il tempo del test.

**Cosa verifica:** tre proprietà in sequenza. (1) Continuità operativa: il
nodo isolato deve continuare ad accettare scritture locali senza errori.
(2) Divergenza reale durante l'isolamento: i due lati devono mostrare
valori diversi mentre la partizione è attiva, a prova che l'isolamento è
davvero efficace (verificato su tutti e quattro i leg della mesh, non solo
uno). (3) Riconciliazione deterministica alla guarigione: i due `entryCSN`
in conflitto vengono catturati mentre la partizione è ancora attiva, usati
per calcolare a priori un'ipotesi di vincitore (il CSN lessicograficamente
maggiore), e dopo la guarigione si verifica che il cluster converga
esattamente su quel valore previsto — non solo che i nodi concordino fra
loro.

*Descrizione dettagliata:* `description_test_network_partition_conflict_resolution.md`

---

## Relazione fra i tre test

I tre test isolano tre modalità di guasto distinte e non sovrapposte:

| Test | Cosa fallisce | Rete | Processo `slapd` |
|---|---|---|---|
| `test_crash_cascading_node.yml` | il processo | intatta | terminato (`kill -9`) |
| `test_concurrent_multimaster_write.yml` | niente (solo concorrenza) | degradata (WAN simulata), ma connessa | sempre vivo |
| `test_network_partition_conflict_resolution.yml` | il collegamento fra nodi | interrotta (netsplit) su una porta specifica | sempre vivo |
