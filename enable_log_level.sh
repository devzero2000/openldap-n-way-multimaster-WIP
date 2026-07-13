sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: cn=config
changetype: modify
replace: olcLogLevel
olcLogLevel: stats sync
EOF
