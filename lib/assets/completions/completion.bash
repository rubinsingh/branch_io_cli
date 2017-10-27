#!/bin/bash

_branch_io_complete()
{
    local cur prev opts global_opts setup_opts validate_opts commands command
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    command="${COMP_WORDS[1]}"

    commands="setup validate"
    global_opts="-h --help -t --trace -v --version"

    setup_opts="$global_opts -L --live-key -T --test-key -D --domains --app-link-subdomain -U --uri-scheme"
    setup_opts="$setup_opts --xcodeproj --target --frameworks --podfile --cartfile"
    # Don't autocomplete the default values here, e.g. --no-force, --pod-repo-update.
    setup_opts="$setup_opts --no-add-sdk --no-validate --force --no-pod-repo-update --commit --no-patch-source"

    validate_opts="$global_opts -D --domains --xcodeproj --target"

    if [[ ${cur} == -* ]] ; then
      case "${command}" in
        setup)
          opts=$setup_opts
          ;;
        validate)
          opts=$validate_opts
          ;;
        *)
          opts=$global_opts
          ;;
      esac
      COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
      return 0
    elif [[ ${prev} == branch_io ]] ; then
      COMPREPLY=( $(compgen -W "${commands} ${global_opts}" -- ${cur}) )
      return 0
    elif [[ ${prev} == --xcodeproj || ${prev} == --podfile || ${prev} == --cartfile ]] ; then
      COMPREPLY=( $(compgen -f ${cur}) )
      return 0
    fi
}
complete -F _branch_io_complete branch_io
