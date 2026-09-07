P=0; F=0; declare -a FAILS
raw(){ curl -sfL "https://raw.githubusercontent.com/$1/$2/$3" 2>/dev/null; }
code(){ curl -sfL -o /dev/null -w "%{http_code}" "https://raw.githubusercontent.com/$1/$2/$3" 2>/dev/null; }
chk(){ # chk <id> <desc> <expected> <actual>
  if [ "$3" = "$4" ]; then P=$((P+1)); printf "  \033[32mLULUS\033[0m  %-9s %s\n" "$1" "$2"
  else F=$((F+1)); FAILS+=("$1: $2 | harap='$3' dapat='$4'")
    printf "  \033[31mGAGAL\033[0m  %-9s %s\n           harap=%s dapat=%s\n" "$1" "$2" "$3" "$4"; fi; }
