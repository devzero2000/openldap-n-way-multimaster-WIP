# Test del cluster OpenLDAP N-Way Multi-Master

Nota descrittiva dei playbook di test presenti in questa directory: nome,
scenario simulato, e cosa ciascuno verifica.

---

## `test_crash_cascading_node.yml`

**Scenario simulato:** crash di processo (`kill -9`) su uno o più nodi del
cluster, sotto WAN simulata — a differenza degli altri due test, qui `slapd`
smette proprio di esistere, non semplicemente di essere raggiungibile.

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
e gli altri due, applicata sopra la WAN simulata — a differenza del crash
test, `slapd` resta vivo e sano su tutti i nodi; viene tagliato solo il
traffico sulla porta di replica LDAPS (636) fra i lati della partizione, per
il tempo del test.

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
| `test_crash_cascading_node.yml` | il processo | degradata (WAN simulata), ma connessa | terminato (`kill -9`) |
| `test_concurrent_multimaster_write.yml` | niente (solo concorrenza) | degradata (WAN simulata), ma connessa | sempre vivo |
| `test_network_partition_conflict_resolution.yml` | il collegamento fra nodi | WAN simulata, interrotta (netsplit) su una porta specifica | sempre vivo |

## Simulazione WAN

Tutti e tre i test girano sotto la WAN simulata
(`stress_test/simulate_wan_mpls_ipsec/simulate_wan_mpls_ipsec.yml`): la
accendono come primo passo del `block` e la spengono sempre nell'`always`,
anche in caso di errore. Dopo l'accensione e dopo lo spegnimento lo stato
reale (qdisc `netem` e regole mangle sulla 636) viene verificato su tutti e 4
i nodi con `assert_wan_state.yml`. Un'interruzione con Ctrl-C non esegue
l'`always`: in quel caso spegnere la WAN a mano con `-e stato=disabled`.
I test non vanno lanciati con `--check`.

## Componenti comuni

Task file da includere con `ansible.builtin.include_tasks` (non sono
playbook), condivisi dai test.

### `assert_clock_skew.yml`

Misura lo scarto reale fra gli orologi dei nodi via SSH e ferma il test oltre
`max_clock_skew_ms`. Serve ai test che dipendono dall'ordine dei CSN.

### `assert_data_integrity.yml` (+ `lib/ldif_integrity.py`)

Verifica che il **contenuto** del DIT sia identico su tutti i nodi indicati,
entry per entry e attributo per attributo, partendo da un dump `slapcat` di
ogni nodo letto via SSH. Opzionalmente verifica anche la coerenza
`member`/`memberOf` nel namespace del test (`integrity_member_scope`):
membri che puntano a entry inesistenti (`DANGLING_MEMBER`), membri senza il
`memberOf` corrispondente (`MISSING_MEMBEROF`), `memberOf` verso gruppi che
non li contengono (`ORPHAN_MEMBEROF`). Ripete il confronto fino a
`integrity_timeout`, perché la replica può essere ancora in corso.

Sostituisce i conteggi dove conta l'integrità: due nodi con lo stesso numero
di entry ma valori diversi risultano convergenti per un conteggio, non per
questo controllo.

- `contextCSN` non si confronta: syncprov la scrive su disco solo ai
  checkpoint, quindi differisce anche a cluster fermo e allineato.
- **Differenza nota**: sulla replica read-only l'entry radice del suffisso ha
  `entryUUID`, `entryCSN` e timestamp diversi da quelli dei master (creata
  localmente al deploy). Non blocca i test, ma viene stampata a ogni run come
  `KNOWN_DIFF` per restare visibile.
- Con `integrity_assert: false` registra solo il risultato
  (`integrity_check`), così il chiamante può fare l'assert dopo il cleanup.

### `service_probe.yml` (+ `lib/service_probe.sh`, `lib/service_probe_report.py`)

Misura l'**erogazione del servizio** durante il guasto, non solo lo stato
finale. Su ogni nodo gira in background una sonda che a ogni giro (default
1s) legge e, sui master, scrive sullo slapd **locale**: in uno scenario
geografico i client stanno nel sito del proprio nodo, e la domanda è se ogni
sito continua a servire. A fine test riporta per nodo disponibilità,
interruzione massima e latenza, e verifica la **durabilità**: ogni scrittura
confermata al client (rc=0) deve esistere su tutti i nodi.

Si usa con `probe_action`:

| Azione | Dove | Cosa fa |
|---|---|---|
| `start` | dopo pre-volo e WAN | rimuove residui `svcprobe.*`, avvia le sonde, verifica che registrino operazioni riuscite |
| `stop` | dopo il ripristino | ferma le sonde, calcola il report, attende la durabilità, cancella le entry `svcprobe.*` |
| `assert` | dopo il cleanup del test | i nodi non in `probe_impacted_nodes` devono restare a `probe_min_availability_pct` (default 100%); nessuna scrittura confermata persa; cleanup riuscito |
| `kill` | nell'`always` | ferma le sonde e rimuove i file (password compresa); tollera nodi irraggiungibili |

La password sta in un file 0600 sui nodi (`ldap* -y`), mai sulla riga di
comando della sonda.
