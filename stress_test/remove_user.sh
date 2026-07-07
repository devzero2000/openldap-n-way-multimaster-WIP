# 1. Genera l'LDIF
python3 generate_delete.py

# 2. Esegui la cancellazione massiva
sudo ldapmodify -c -H ldapi:/// -D "cn=admin,dc=example,dc=com" -w "openldap" -f /tmp/delete_stress_test_data.ldif

# 3. Rimuovi il file temporaneo pesante
rm /tmp/delete_stress_test_data.ldif
