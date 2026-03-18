typeset -U path PATH

for candidate in "/opt/homebrew/bin" "/usr/local/bin" "/opt/homebrew/opt/qt@5/bin"; do
  if [[ -d "$candidate" ]]; then
    path=("$candidate" $path)
  fi
done

if [[ -d "/opt/homebrew/opt/openssl@3" ]]; then
  export OPENSSL_ROOT_DIR="/opt/homebrew/opt/openssl@3"
elif [[ -d "/usr/local/opt/openssl@3" ]]; then
  export OPENSSL_ROOT_DIR="/usr/local/opt/openssl@3"
fi
