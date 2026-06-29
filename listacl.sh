#!/bin/bash

# Fot the main database
sudo ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config '(olcDatabase={1}mdb)' olcAccess

# For the frontend database
sudo ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config '(olcDatabase={-1}frontend)' olcAccess

# ACLs of the slapd-config database
#
sudo ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config '(olcDatabase={0}config)' olcAccess

#get all the acl
