echo "Q" | openssl s_client -connect 127.0.0.1:636 -CAfile /etc/ldap/sasl2/ca.crt 2>/dev/null | grep -E "Protocol|Cipher"
echo "Q" | openssl s_client -connect 127.0.0.1:636   -CAfile /etc/ldap/sasl2/ca.crt 2>/dev/null   | grep -E "Protocol|Cipher|Temp Key"
