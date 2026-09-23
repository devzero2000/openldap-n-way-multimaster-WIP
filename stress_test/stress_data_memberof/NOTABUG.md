# Problematiche di mancata sincronizzazione

In fase di test popolando il db ldap su node 1 con lo script
populate_stress_data.yml si è riscontrato come su node2 e node3 mancassero
alcuni utenti e gruppi invece presenti su node1. Questo pur in presenza di
un apparente stato di salute della sincronizzazione



     vagrant@ubuntu24lts1:~/openldap-n-way-multimaster-WIP$ sh
     check_contextCSN.sh
        contextCSN: 20260709224441.477933Z#000000#001#000000 contextCSN:
        20260709220132.455471Z#000000#002#000000 contextCSN:
        20260709220132.479524Z#000000#003#000000
    vagrant@ubuntu24lts1:~/openldap-n-way-multimaster-WIP$ sh
    check_direct_sync.sh --- VERIFICA DIRETTA NODO 2 <-- NODO 1 --- [OK]
    Nodo 2 è in sync con Nodo 1.

    --- VERIFICA DIRETTA NODO 3 <-- NODO 1 --- [OK] Nodo 3 è in sync con
    Nodo 1.

    =====================================================================
    [STATUS FINALE] CLUSTER ALLINEATO: Tutti i nodi sono in sync con il
    Nodo 1.  vagrant@ubuntu24lts1:~/openldap-n-way-multimaster-WIP$
    sh check_ldap_syncrepl_status_nodes.sh
    =====================================================================
       AVVIO MONITORAGGIO CIRCOLARE DELLA REPLICA (N-WAY RING CHECK)
    =====================================================================

    [TEST 1/3] Verifica consistenza: ubuntu24lts2 <-- ubuntu24lts1...
    OK - directories are in sync (W:10 - C:15) [TEST 2/3] Verifica
    consistenza: ubuntu24lts3 <-- ubuntu24lts2...  OK - directories are
    in sync (W:10 - C:15) [TEST 3/3] Verifica consistenza: ubuntu24lts1
    <-- ubuntu24lts3...  OK - directories are in sync (W:10 - C:15)
    =====================================================================
    [OK] Ciclo di monitoraggio completato. Tutti i nodi sono coerenti.
    vagrant@ubuntu24lts1:~/openldap-n-way-multimaster-WIP

L'unico modo per verificare lo stato reale era effettuare uno slapcat come
quello di seguito su ognuno dei tre nodi

    sudo slapcat -b "dc=example,dc=com" -a
    "(entryDN:dnSubtreeMatch:=ou=People,dc=example,dc=com)" | grep -c "dn: "

Il risultato giusto di quel comando, con il nostro script di popolazione di
esempio, è 30001. Purtroppo dopo la prima esecuzione si è notato che node2
e node1 avevavo valori seppure uguali ma leggermente inferiori a node1. Poi
dopo un po' di tempo addirittura node1 si è allineato ai valori(incompleti)
di node2 e node3. Infine rieseguendo in questa situazione lo script di
popolazione massiva, che è idempotente, finalmente i nodi si sono allineati.

Facendo delle analisi su quanto reperibile dal web in modo piu' o meno
ufficiale questo limite architetturale, che si puo' verificare in modo non
deterministico, è ampiamente noto all'interno della community di OpenLDAP
ed è documentato e discusso principalmente in tre canali ufficiali:

1. OpenLDAP Issue Tracking System (ITS) Il comportamento del "sorpasso"
dei thread e del mancato allineamento del contextCSN è tracciato in diverse
segnalazioni storiche di bug (ITS).

La discussione fondamentale e più dettagliata si trova sotto l'ITS#7223
(intitolato proprio "syncrepl missed updates with multi-threaded write load").

Altri riferimenti correlati allo stesso problema di concorrenza sotto carichi
massivi si trovano in ITS#6634 e ITS#8443. In questi ticket, i core developer
di OpenLDAP (tra cui Howard Chu) spiegano chiaramente come la sovrapposizione
temporale dei commit in thread paralleli possa causare uno "skew" (una
distorsione) del CSN rispetto a quello che il consumatore ha già registrato.

2. Le Man Page di Slapd (slapd.accesslog e slapo-syncprov) Nelle pagine
di manuale ufficiali, in particolare in quella dell'overlay che gestisce il
provider di replica (man slapo-syncprov), viene descritto il funzionamento del
meccanismo di checkpoint (syncprov-checkpoint).  La documentazione evidenzia
che il contextCSN non viene scritto costantemente a ogni micro-operazione
per preservare le performance di scrittura sul disco. Viene spiegato che in
scenari ad alto parallelismo (multi-threading), se la sessione si interrompe
prima del checkpoint, lo stato del cookie inviato potrebbe non riflettere
l'esatto stato transazionale delle entry inferiori a quel timestamp.

3. OpenLDAP Software Mailing List (Archives) Nelle liste di discussione
ufficiali (openldap-technical e openldap-software), questo fenomeno viene
regolarmente citato quando gli amministratori di sistema segnalano "buchi"
intermittenti di record dopo importazioni massive (proprio come nel caso di
stress test da decine di migliaia di utenti).

Nelle risposte ufficiali dei manutentori viene specificato che:

*La Syncrepl garantisce la consistenza eventuale ("eventual consistency")
assumendo che l'ordine cronologico dei CSN sia lineare. Sotto carichi
paralleli estremi, la linearità della scrittura su disco può saltare
rispetto all'assegnazione del CSN in memoria*.

È proprio per via di questa documentazione ufficiale che, per i caricamenti
massivi di dati (come il popolamento da 30k utenti), la raccomandazione
standard della community è quella di eseguire l'importazione iniziale offline
usando slapadd (che scrive direttamente nel database saltando il motore dei
thread di slapd), oppure di serializzare le richieste nel client/playbook
per evitare la parallelizzazione estrema.

