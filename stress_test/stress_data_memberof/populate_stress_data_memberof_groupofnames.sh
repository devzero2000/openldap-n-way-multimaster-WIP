ldif_file="populate_stress_data_memberof_groupofnames.ldif"
name_ldif_file="${ldif_file%.*}"
rm -f $ldif_file
unzip $name_ldif_file.zip
ansible-playbook ../../restore_master_from_backup.yml --extra-vars "backup_file=$(pwd)/$ldif_file" -e confirm_wipe=SI-CONFERMO-IL-RIPRISTINO
rm $ldif_file
