ldapsearch -x -D "cn=admin,dc=example,dc=com" -w openldap \
  -b "cn=accesslog" -s sub "(objectClass=auditWriteObject)" reqType reqResult reqDN | head -50
# Conteggio entry attuali nell'accesslog
ldapsearch -x -D "cn=admin,dc=example,dc=com" -w openldap \
  -b "cn=accesslog" -s one "(objectClass=auditWriteObject)" dn | grep -c "^dn:"

# Dimensione fisica reale del database sul disco
sudo du -sh /var/lib/ldap/accesslog/

# Statistiche interne LMDB (se hai mdb_stat installato, pacchetto lmdb-utils)
sudo mdb_stat -e /var/lib/ldap/accesslog/
