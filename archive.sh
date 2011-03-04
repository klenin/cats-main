tar -c -z -f `date "+cats_%Y_%m_%d.tar.gz"` \
--exclude 'backup/*' --exclude 'static/*' --exclude '*.gz' --exclude '*.gdb' --exclude '*.fdb' --exclude 'judge/solutions/*' \
--exclude '*.exe' --exclude 'cgi-bin/download/*' --exclude '*.pch' --exclude '*.pdb' \
--exclude '*.ilk' --exclude '*.obj' --exclude '*.log' --exclude '*.idb' \
--exclude '*.zip' --exclude '*.ncb' --exclude 'rank_cache/*' *