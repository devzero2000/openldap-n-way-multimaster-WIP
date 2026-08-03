ldapsearch -x -H ldap://localhost -D "cn=admin,dc=example,dc=com" -w "openldap" -b "ou=People,dc=example,dc=com" -s one "(uid=*crash*)" dn | grep "^dn:" | sed 's/^dn: //' > utenti_da_cancellare.txt
