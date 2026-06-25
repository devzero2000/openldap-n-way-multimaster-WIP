ldapsearch -x -D "cn=admin,dc=example,dc=com" -w openldap -b "dc=example,dc=com" -s base + | grep contextCSN
