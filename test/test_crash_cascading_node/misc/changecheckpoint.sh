for h in ubuntu24lts1.example.com ubuntu24lts2.example.com ubuntu24lts3.example.com ubuntu24lts4.example.com; do
  echo "=== $h ==="
  ssh "$h" "sudo ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcOverlay={0}syncprov,olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcSpCheckpoint
olcSpCheckpoint: 1000 10
EOF"
done
