#
# Taken from https://www.openldap.org/faq/data/cache/1366.html
#
#To read the name of the (sub)entry holding the controlling (sub)schema from an entry, say dc=example,dc=com, one could issue the following command:

ldapsearch -x -LLL -b dc=example,dc=com -s base subschemaSubentry
#The value of the subschemaSubentry attribute is the name of the (sub)entry holding the controlling (sub)schema. Note that on current versions of slapd(8), the server supports only a single schema and its always named cn=Subschema, however future versions of slapd(8) might support multiple subschema subentries. Well-behaved clients should not shortcut this procedure.
#Armed with the name of the (sub)entry holding the (sub)schema, one can then read the desired attributes from this (sub)entry. For instance, one might issue

ldapsearch -x -LLL -b cn=Subschema -s base '(objectClass=subschema)' attributeTypes dITStructureRules objectClasses nameForms dITContentRules matchingRules ldapSyntaxes matchingRuleUse
#In servers which supports RFC 3673 you can use a short form:
ldapsearch -x -LLL -b cn=Subschema -s base '(objectClass=subschema)' +
#This command will generally produce pages of output, hence it is often appropriate to request, by name, only thos1\e attributes of interest.
