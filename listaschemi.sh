ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// \
  -b "cn=schema,cn=config" \
  "(olcObjectClasses=*)" olcObjectClasses
