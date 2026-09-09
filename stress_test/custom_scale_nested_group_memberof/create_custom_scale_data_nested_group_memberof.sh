rm -f create_custom_scale_data_nested_group_memberof.ldif
unzip create_custom_scale_data_nested_group_memberof.zip
ansible-playbook ../../restore_master_from_backup.yml --extra-vars 'backup_file=stress_test/custom_scale_nested_group_memberof/create_custom_scale_data_nested_group_memberof.ldif' -e confirm_wipe=SI-CONFERMO-IL-RIPRISTINO

rm create_custom_scale_data_nested_group_memberof.ldif
