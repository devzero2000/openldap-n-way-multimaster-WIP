ldapsearch -x -H ldap://ubuntu24lts2.example.com:389 -D "cn=nwayreplicator,ou=system,dc=example,dc=com" -w nwayreplicator -b "dc=example,dc=com" -s base "objectClass=*"
