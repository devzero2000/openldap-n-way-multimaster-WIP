ldif_file="create_custom_scale_data_nested_group_memberof.ldif"
name_ldif_file="${ldif_file%.*}"
rm -f $ldif_file
unzip $name_ldif_file.zip
ansible-playbook ../../restore_master_from_backup.yml --extra-vars "backup_file=$(pwd)/$ldif_file" -e confirm_wipe=SI-CONFERMO-IL-RIPRISTINO
rm $ldif_file
