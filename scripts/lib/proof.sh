proof_kinds=()
proof_args=()
proof_shots=()
proof_error=""

proof_load() {
  local file=$1 number=0 line kind rest type label status
  proof_kinds=()
  proof_args=()
  proof_shots=()
  proof_error=""
  [ -f "$file" ] || { proof_error="no proof file at $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    number=$((number + 1))
    line=${line#"${line%%[![:space:]]*}"}
    case "$line" in "" | "#"*) continue ;; esac
    kind=${line%%[[:space:]]*}
    rest=${line#"$kind"}
    rest=${rest#"${rest%%[![:space:]]*}"}
    rest=${rest%"${rest##*[![:space:]]}"}
    case "$kind" in
      set)
        local key value
        read -r key type value <<< "$rest"
        case "$type" in
          string | bool | int | float) ;;
          *) proof_error="line $number: set needs a key, a type (string, bool, int or float) and a value"; return 1 ;;
        esac
        [ -n "$value" ] || { proof_error="line $number: set needs a key, a type (string, bool, int or float) and a value"; return 1; }
        [[ "$key" =~ ^[A-Za-z0-9._-]+$ ]] || { proof_error="line $number: bad defaults key $key"; return 1; }
        ;;
      launch)
        [ -n "$rest" ] || { proof_error="line $number: launch needs arguments"; return 1; }
        ;;
      run)
        [ -n "$rest" ] || { proof_error="line $number: run needs a debug command"; return 1; }
        ;;
      shot)
        label=$rest
        [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || { proof_error="line $number: a shot label is letters, digits, dot, dash or underscore"; return 1; }
        case " ${proof_shots[*]-} " in
          *" $label "*) proof_error="line $number: the shot label $label is already used"; return 1 ;;
        esac
        proof_shots+=("$label")
        ;;
      check)
        [ -n "$rest" ] || { proof_error="line $number: check needs a jq filter"; return 1; }
        printf 'null\n' | jq -e "$rest" >/dev/null 2>&1
        status=$?
        [ "$status" -ne 2 ] && [ "$status" -ne 3 ] || { proof_error="line $number: jq cannot compile the filter: $rest"; return 1; }
        ;;
      *)
        proof_error="line $number: unknown directive $kind (use set, launch, run, shot or check)"
        return 1
        ;;
    esac
    proof_kinds+=("$kind")
    proof_args+=("$rest")
  done < "$file"
  case " ${proof_kinds[*]-} " in
    *" check "*) ;;
    *) proof_error="the proof has no check line"; return 1 ;;
  esac
}
