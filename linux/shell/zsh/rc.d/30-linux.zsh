typeset -U path PATH

for candidate in "/usr/local/bin" "/usr/local/sbin"; do
  if [[ -d "$candidate" ]]; then
    path=("$candidate" $path)
  fi
done
