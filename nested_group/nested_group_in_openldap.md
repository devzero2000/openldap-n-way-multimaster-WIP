# Supporto nested group in OpenLDAP


In primo luogo dalla documentazione l'overlay slapo-memberof standard di
OpenLDAP non supporta nativamente i Nested Groups (i gruppi annidati) nel modo
in cui li intende Active Directory o altri sistemi Enterprise. Ecco esattamente
cosa fa, cosa supporta e dove si ferma l'overlay standard in base a quanto
abbiamo potuto vedere dalla documentazione disponibile:

 

 - Cosa supporta l'overlay (Il comportamento standard)

L'overlay supporta unicamente un meccanismo piatto di manutenzione automatica
guidata da eventi di scrittura. Funziona solo da Gruppo a Utente (1 livello):
Quando tu scrivi nel database che l'utente uid=mario.rossi è un valore
dell'attributo member dentro il gruppo cn=Deploy-Stage1, l'overlay intercetta
questa scrittura e aggiunge in automatico l'attributo virtuale memberOf:
cn=Deploy-Stage1 nel record di Mario Rossi.

Supporta classi di gruppo e attributi personalizzabili: Tramite le direttive
olcMemberOfGroupOC e olcMemberOfMemberAD (che abbiamo configurato nel tuning),
puoi dirgli di monitorare classi diverse (come groupOfNames o
groupOfUniqueNames) e attributi diversi (come member o uniqueMember).

  - Cosa succede esattamente se inserisci un gruppo dentro un altro gruppo?

Se inserisci il gruppo cn=Deploy-Stage1 come valore dell'attributo member
all'interno del gruppo padre cn=Cloud-Architect, l'overlay si comporta
esattamente così:

Vede che è stata scritta una modifica sul gruppo Cloud-Architect.  Prende il DN
del membro inserito (che in questo caso è cn=Deploy-Stage1,ou=groups,...).  Va
sulla entry di quel membro (cn=Deploy-Stage1) e aggiunge a quel gruppo
l'attributo virtuale memberOf: cn=Cloud-Architect.

L'overlay si ferma qui. Non implementa alcuna logica ricorsiva. Non sa e non si
cura del fatto che cn=Deploy-Stage1 sia a sua volta un gruppo contenente degli
utenti. Di conseguenza, non scenderà mai a cascata sui record degli utenti
interni (mario.rossi) per aggiornare il loro memberOf.

 - Perché nel manuale o in molti articoli si parla di "supporto al nesting"?

Spesso si genera confusione perché l'overlay permette dal punto di vista
sintattico di associare l'attributo memberOf anche a un oggetto di tipo gruppo
(se la configurazione lo consente), ma questo serve solo a fini di inventario
piatto (ovvero sapere a quali gruppi "padre" appartiene un determinato
"sottogruppo"). Non automatizza in alcun modo l'ereditarietà dei permessi o dei
membri delle entry foglia (gli utenti) in fase di lettura.

 - In conclusione: Cosa supporta ESATTAMENTE OpenLDAP nativamente?

Nativamente, tramite slapo-memberof, OpenLDAP supporta solo l'associazione
diretta a un singolo livello tra un oggetto (sia esso utente o gruppo) e il suo
contenitore immediato.

Se l'applicazione client esegue una ricerca basata sul filtro
(memberOf=cn=Cloud-Architect,...), OpenLDAP restituirà solo le entry che hanno
esplicitamente scritto quell'attributo nel proprio record. Per questo motivo nel
nostro test veniva estratto solo Giovanni Bianchi (membro diretto) ed escluso
Mario Rossi (membro del sottogruppo).

