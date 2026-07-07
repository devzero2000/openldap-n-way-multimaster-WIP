#!/usr/bin/env python3
# -*- coding: utf-8 -*-

suffix = "dc=example,dc=com"
delete_ldif_path = "/tmp/delete_stress_test_data.ldif"

with open(delete_ldif_path, "w") as f:
    # 1. Rimozione dei 40 Gruppi Cloud Architect
    for i in range(1, 41):
        f.write(f"dn: cn=architect.{i},ou=groups,{suffix}\n")
        f.write("changetype: delete\n\n")
    
    # 2. Rimozione dei 30.000 Gruppi Periferici
    for i in range(1, 30001):
        f.write(f"dn: cn=group.{i},ou=groups,{suffix}\n")
        f.write("changetype: delete\n\n")
    
    # 3. Rimozione dei 30.000 Utenti
    for i in range(1, 30001):
        f.write(f"dn: uid=user.{i},ou=People,{suffix}\n")
        f.write("changetype: delete\n\n")

print(f"File LDIF generato con successo in: {delete_ldif_path}")
