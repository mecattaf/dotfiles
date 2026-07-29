{
  coreutils,
  netcat-openbsd,
  writeShellApplication,
}:

writeShellApplication {
  name = "brother-print-text";

  runtimeInputs = [
    coreutils
    netcat-openbsd
  ];

  text = ''
    usage() {
      cat <<'EOF'
    usage: brother-print-text [--] <text...>
           printf '%s' <text> | brother-print-text

    Send plain text directly to the Brother HL-L2445DW raw TCP port.
    This path is for trivial text only; send PDF and other rendered files with lp.
    EOF
    }

    case "''${1-}" in
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        ;;
    esac

    if (( $# == 0 )) && [[ -t 0 ]]; then
      usage >&2
      exit 2
    fi

    printer_host="''${BROTHER_PRINT_TEXT_HOST:-192.168.1.38}"
    printer_port="''${BROTHER_PRINT_TEXT_PORT:-9100}"

    if [[ ! "$printer_host" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
      echo "brother-print-text: invalid printer host: $printer_host" >&2
      exit 2
    fi
    if [[ ! "$printer_port" =~ ^[0-9]+$ ]]; then
      echo "brother-print-text: invalid printer port: $printer_port" >&2
      exit 2
    fi

    if (( $# > 0 )); then
      payload="$*"
    else
      payload=$(cat)
    fi
    if [[ -z "$payload" ]]; then
      echo "brother-print-text: refusing to send an empty page" >&2
      exit 2
    fi

    printf '%s\r\n\f' "$payload" \
      | timeout 15s nc -N -w 10 "$printer_host" "$printer_port"

    printf 'sent raw text to Brother at %s:%s\n' "$printer_host" "$printer_port" >&2
  '';

  meta.mainProgram = "brother-print-text";
}
