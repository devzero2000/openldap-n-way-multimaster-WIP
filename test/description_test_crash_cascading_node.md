## Parte 1: Architettura e Funzionamento del Playbook
(`test_crash_cascading_nodes.yml`)

Il playbook ha lo scopo di misurare la resilienza, la consistenza e le
capacità di sincronizzazione delta dell'overlay `slapo-syncprov` su un
cluster OpenLDAP N-Way Multi-Master soggetto a partizionamenti di rete e
crash a cascata dei nodi consumer.

```text
                +-----------------------------------------+
                |           Ansible Control Node          |
                +-----------------------------------------+
                                     |
               (Orchestratore via loopback locale & SSH)
                                     v
+-----------------------+   +-----------------------+
+-----------------------+ |        NODE 1         |   |        NODE 2         |
|        NODE 3         | | ubuntu24lts1          |   | ubuntu24lts2          |
| ubuntu24lts3          | | (Write Target & MDB)  |   | (Consumer -> Outage 1)|
| (Consumer -> Outage 2)| +-----------------------+   +-----------------------+
+-----------------------+
            |                           |                           |
            +======== WAN (Netem: 50ms Latency / 0.1% Loss) ========+

```

### Flusso Logico delle Fasi

1. **Iniezione Asincrona ad Alta Frequenza (Fase 1):** Viene eseguito uno
script Python in background direttamente su `node1` (`delegate_to: "{{
node1 }}"`). Lo script si connette in locale (`ldaps://127.0.0.1:636`) ed
inserisce 2.000 oggetti LDAP (`uid=crash.user.X`) a una velocità di circa
200 operazioni al secondo (`time.sleep(0.005)`). In questo modo l'iniezione
non risente di eventuali problemi sulle sessioni SSH remote.


2. **Simulazione dei Crash a Cascata (Fase 2):** * **Crash 1 (T+2s):** Viene
arrestato forzatamente il servizio `slapd` su `node2` (`systemctl stop slapd`).


* **Crash 2 (T+6s):** Dopo altri 4 secondi viene arrestato il servizio su
`node3`, lasciando `node1` isolato mentre continua a ricevere la carica
di scritture.




3. **Attesa Completamento Scritture (Fase 4):** Il controller monitora il
PID dello script di iniezione in `/tmp/async_load.pid` su `node1` mediante
un ciclo `kill -0` finché tutti i record non sono stati scritti sul DB MDB.


4. **Ripristino e Misurazione della Convergenza (Fase 3):** I servizi `slapd`
su `node2` e `node3` vengono riavviati simultaneamente. Uno script di audit
interroga i tre nodi e calcola i millisecondi esatti necessari affinché la
replica Delta Sync di `syncprov` riallinei completamente i record di `node2`
e `node3` a quelli di `node1`.


5. **Cleanup e Ripristino DIT (Fase 4):** Tutti i 2.000 utenti di test inseriti
in `ou=People` vengono eliminati e i file di tracciamento `/tmp/async_load.*`
rimossi.



---

## Parte 2: Discussione dei Risultati dell'Audit e del Modulo `netem`

L'output dell'audit conferma che la simulazione di rete WAN (MPLS + IPSec) è
attiva, corretta e conforme su tutti e tre i nodi del cluster (`ubuntu24lts1`,
`ubuntu24lts2`, `ubuntu24lts3`).

### 1. Validazione della Rete e di Traffic Control (`tc`)

L'audit conferma la presenza dell'infrastruttura di modellazione del traffico
a livello di Kernel Linux:

* **Qdisc Root HTB (`1:`) e Classe (`1:10`):** Il meccanismo Hierarchical
Token Bucket è attivo per limitare e incanalare la banda.  * **Parametri
`netem` applicati:** * **Latenza / Jitter:** Configurati a **50 ms ± 2 ms**.
* **Packet Loss:** Configurato allo **0.1%**.


* **Filtri e Marcatura Pacchetti:** * Le regole `iptables` nella catena
`POSTROUTING` della tabella `mangle` contrassegnano i pacchetti TCP in uscita
sulle porte **389 (LDAP)** e **636 (LDAPS)** con il valore `FWMARK 10`.
* Il filtro `tc` intercetta i pacchetti con `FWMARK 10` e li dirotta nella
classe `1:10` dove agisce `netem`.



### 2. Analisi della Discrepanza: Ping ICMP vs. Traffico LDAP Marcato

Guardando il report dell'audit si nota che il ping ICMP riporta tempi di
risposta brevissimi:

* `ubuntu24lts1`: `rtt min/avg/max = 0.028/0.047/0.062 ms` * `ubuntu24lts2`:
`rtt min/avg/max = 0.026/0.045/0.065 ms` * `ubuntu24lts3`: `rtt min/avg/max =
0.025/0.039/0.051 ms`

#### Perché il ping misura ~0.045 ms se `netem` è impostato a 50 ms?

Questo comportamento è **assolutamente corretto ed è stato progettato
esattamente così**:

1. **Selettività delle Regole di Mangle:** La regola `iptables` filtra
esclusivamente il traffico TCP indirizzato o proveniente dalle porte
`389` e `636`. I pacchetti ICMP inviati dal comando `ping` non hanno un
header TCP con tali porte, quindi bypassano la classe `1:10` e attraversano
l'interfaccia di rete senza subire alcun ritardo artificiale.  2. **Impatto
Reale su Syncrepl / LDAPS:** Quando i nodi comunicano tra loro per la replica
via LDAPS (`ldaps://...:636`), il traffico viene marcato con `FWMARK 10`
e subisce la latenza reale di **50 ms ad ogni tratta** (portando l'RTT di
un handshake TCP/TLS o di un pacchetto di sync a oltre 100 ms) unitamente
allo drop casuale dello 0.1% dei pacchetti. Questo è stato verificato con
tcping.

---

## Sintesi Finale

* **Isolamento Perfetto dell'Ambiente di Test:** La configurazione con
`iptables` + `tc` + `netem` permette di simulare un collegamento WAN reale
(MPLS/IPSec a 50 ms) limitatamente al protocollo LDAP, senza rallentare le
sessioni SSH di gestione o gli altri servizi di sistema.  * **Eccellente
Performance del Cluster:** Il tempo di convergenza registrato nel test
(**1474 ms**) dimostra che, nonostante una latenza di rete di 50 ms e
perdite di pacchetti attive sulle porte 636, la configurazione dei buffer
in RAM (`olcSpSessionlog: 10000`) consente a `slapo-syncprov` di eseguire il
riallineamento delta a caldo in meno di un secondo e mezzo senza costringere
i nodi a un re-sync completo da disco.
