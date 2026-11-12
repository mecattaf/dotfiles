# Every /run/current-system/sw/bin/<command> that a staged Scheduled item
# or workflow names must be in the NAS system closure. An item that names a
# launcher the NAS does not install ends at once when armed (fleet-nightly,
# 12 Nov 2026: fleet-update-start comes from the unmerged #642).
#
# pending.json lists the commands that are knowingly not installed yet, each
# with the change that provides it. An entry that is installed fails the
# check too, so the list empties itself when the provider lands.
{ pkgs, configurations }:
let
  sw = configurations.nas.config.system.path;
  agency = ../../pkgs/scheduled/test/fixtures/master/.agency;
  pending = ./pending.json;
in
pkgs.runCommand "scheduled-commands"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    status=0
    names=$(find ${agency} -type f \( -name '*.jsonc' -o -name '*.js' \) \
      -exec grep -ohE '/run/current-system/sw/bin/[A-Za-z0-9._+-]+' {} + \
      | sed 's|.*/||' | sort -u)
    for name in $names; do
      why=$(jq -r --arg n "$name" '.[$n] // empty' ${pending})
      if [ -x "${sw}/bin/$name" ]; then
        if [ -n "$why" ]; then
          echo "FAIL $name: installed now; remove it from pending.json"
          status=1
        else
          echo "ok   $name"
        fi
      elif [ -n "$why" ]; then
        echo "pending $name: $why"
      else
        echo "FAIL $name: named by a staged item, not in the NAS system closure"
        status=1
      fi
    done
    for name in $(jq -r 'keys[]' ${pending}); do
      case " $(echo $names) " in
        *" $name "*) ;;
        *) echo "FAIL $name: in pending.json but no staged item names it"; status=1 ;;
      esac
    done
    [ "$status" -eq 0 ] && touch "$out"
    exit "$status"
  ''
