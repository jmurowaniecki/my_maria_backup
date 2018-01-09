#!/usr/bin/env bash
#
# TITLE       : Backup tool.
# DESCRIPTION : A simple and reliable backup script.
# AUTHOR      : John Murowaniecki <john@compilou.com.br>
# DATE        : 20180105
# VERSION     : 0.1.0-0
# USAGE       : bash backup_datrabase.sh or ./backup_datrabase.sh or ..
# REPOSITORY  : https://github.com/jmurowaniecki/your_project
# ----------------------------------------------------------------------------
#
APP=$0
APP_PATH=$(pwd)
APP_TITLE=" 🖫  Database tool"
APP_RECIPES=YES
APP_MAJOR=0
APP_MINOR=1
APP_REVISION=0
APP_PATCH=0

declare -A DATABASES

CONFIG_FILE=".$(echo "$0" | sed -E 's/.*\/(.*)$/\1/g')"
TARGET_FILE="${CONFIG_FILE}"

function backup {
    case "$1" in
        GZIP) gzip "$2" && return;;
        FREE)
            backup=($(ls -t ./*-*.sql.gz))
            delete=$((${#backup[@]}-10))
            if [ $delete -gt 0 ]
            then for ((n=10; n<${#backup[@]}; n++))
                do rm "${backup[$n]}"
                done
            fi
            return
            ;;

        EXEC)
            ALIAS="$2"
            HOSTNAME="$3"
            DATABASE="$4"
            USERNAME="$5"
            PASSWORD="$6"
            FILENAME="${ALIAS}-$(date +'%Y%m%d%H%M%S').sql"

            $_e "Dumping ${ALIAS}.."

            mysqldump \
                --compress \
                --add-locks \
                            \
                -u"${USERNAME}" \
                -p"${PASSWORD}" \
                -h"${HOSTNAME}" \
                                \
                "${DATABASE}" > "${FILENAME}" && \
                    backup GZIP "${FILENAME}"
            return
            ;;

        SAVE)
            $_e -n > "${TARGET_FILE}"

            for source in "${DATABASES[@]}"
            do  $_e "backup ${source}" >> "${TARGET_FILE}"
            done

            return
            ;;

        *)
            ALIAS="$1"
            HOSTNAME="$2"
            DATABASE="$3"
            USERNAME="$4"
            PASSWORD="$5"

            DATABASES["${ALIAS}"]="${ALIAS} ${HOSTNAME} ${DATABASE} ${USERNAME} ${PASSWORD}"
    esac
}

function checkConfig {

    if [ $# -gt 0 ]
    then
        case "$1" in
            ALIAS)    $_e "$2";;
            HOSTNAME) $_e "$3";;
            DATABASE) $_e "$4";;
            USERNAME) $_e "$5";;
            PASSWORD) $_e "$6";;

            EXISTS)
                ALIAS="$2"
                HOSTNAME="$3"
                DATABASE="$4"
                USERNAME="$5"
                PASSWORD="$6"
                FILE_ERROR=$(tempfile)

                $_e "SHOW DATABASES;" | mysql \
                    -u"${USERNAME}" \
                    -p"${PASSWORD}" \
                    -h"${HOSTNAME}" \
                    -N -r "${DATABASE}" 2>"${FILE_ERROR}" >>"${FILE_ERROR}" && \
                       ERROR=$(cat "$FILE_ERROR")

                ($_e "$ERROR" | grep  -q 'ERROR 1049') && MESSAGE='UNKNOW_DATABASE'
                ($_e "$ERROR" | grep  -q 'ERROR 2005') && MESSAGE='UNREACHABLE_SERVER'
                ($_e "$ERROR" | grep  -q 'ERROR 1045') && MESSAGE='ACCESS_DENIED'

                rm "${FILE_ERROR}"
                $_e "${MESSAGE}"
            ;;

            *)
                ALIAS="$1"
                HOSTNAME="$2"
                DATABASE="$3"
                USERNAME="$4"
                PASSWORD="$5"
                FILE_ERROR=$(tempfile)

                status_db="${Cg}"
                status_sr="${Cg}"

                $_e "SHOW DATABASES;" | mysql \
                    -u"${USERNAME}" \
                    -p"${PASSWORD}" \
                    -h"${HOSTNAME}" \
                    -N -r "${DATABASE}" 2>"${FILE_ERROR}" >>"${FILE_ERROR}" && \
                       ERROR=$(cat "$FILE_ERROR")
                ($_e "$ERROR" | grep  -q 'ERROR 1049') && status_db="${Cr}" && MESSAGE='Unknow database.'
                ($_e "$ERROR" | grep  -q 'ERROR 2005') && status_db="${Cr}" && MESSAGE='Cannot connect to server.'      && status_sr="${Cr}"
                ($_e "$ERROR" | grep  -q 'ERROR 1045') && status_db="${Cr}" && MESSAGE="Access denied for ${USERNAME}." && status_sr="${Cr}"

                rm "${FILE_ERROR}"

                $_e "${status_sr}${HOSTNAME}${Cn}\t${status_db}${DATABASE}${Cn}\t${MESSAGE}"
        esac

        return
    fi
    for source in "${HOME}/${CONFIG_FILE}" "${CONFIG_FILE}"
    do  src "${source}"
    done
}

function execute {
    # Perform backup from every database configured.

    checkConfig

    success message "${Cb}${#DATABASES[@]}${Cn} databases processed."

    $_e "Cleaning old entries.."
    backup FREE

    for source in "${DATABASES[@]}"
    do  $_e "$source"
        # shellcheck disable=SC2086
        time backup EXEC ${source}
    done

    success
}

function restore {
    # Restore database from backup.

    checkConfig

    function last {
        #restore: Restore last backup desired.
        DATABASE="$1"
        success message "Database ${Cb}${DATABASE}${Cn} restored."

        [[ "${DATABASE}" == "" ]] && \
            fail "Use ${Cb}$0 restore last databaseALIAS${Cn} to restore your database.\n\n$(manage list)"

        FOUND=$(ls -t ./${DATABASE}-*.sql.gz | head -n1)

        [ -e "${FOUND}" ]  && \
            confirmYesNo "Do you wish restore ${Cb}\`${FOUND}\`${Cn} dump? It may take some time."
        [ "$confirmYesNo" == 'Y' ] && \
            from "${DATABASE}" "${FOUND}" && \
            success
    }

    function reanimate {

        ALIAS=
        HOSTNAME=
        DATABASE=
        USERNAME=
        PASSWORD=
        FILENAME="$1"
        TARGET="$3"
        FILE_ERROR=$(tempfile)
        FILE_UNZIP=$(tempfile)

        function extractData {
            ALIAS="$1"
            HOSTNAME="$2"
            DATABASE="$3"
            USERNAME="$4"
            PASSWORD="$5"
        }

        extractData ${DATABASES[$2]}

        $_e "CREATE DATABASE ${TARGET};" | mysql \
            -u"${USERNAME}" \
            -p"${PASSWORD}" \
            -h"${HOSTNAME}" #2>"${FILE_ERROR}" >>"${FILE_ERROR}" && \
            #    ERROR=$(cat "$FILE_ERROR")

        while [ -e "${FILE_UNZIP}" ]; do $_e -n '.'; sleep 3; done&

        gunzip "$1" --to-stdout | mysql \
            -u"${USERNAME}" \
            -p"${PASSWORD}" \
            -h"${HOSTNAME}" "${TARGET}"

        rm  "${FILE_UNZIP}"
        rm  "${FILE_ERROR}"

        $_e
    }

    function from {
        #restore: Restore from specific backup.
        DATABASE="$1"
        FILEDUMP="$2"
        success message "Restoring database ${Cb}${DATABASE}${Cn} from ${FILEDUMP}.."

        # shellcheck disable=SC2086
        CHECK=$(checkConfig EXISTS ${DATABASES[$DATABASE]})

        case "${CHECK}" in
            UNKNOW_DATABASE)
                reanimate "${FILEDUMP}" "${DATABASE}" "${DATABASE}" && \
                success
                ;;

            UNREACHABLE_SERVER)
                MESSAGE="Cannot reach server ${Cb}$(checkConfig HOSTNAME ${source})${Cn}."
            ;;

            ACCESS_DENIED)
                MESSAGE="Access denied for user ${Cb}$(checkConfig USERNAME ${source})${Cn}."
            ;;

            *)
                $_e "Database already exists: ${Cb}${DATABASE}${Cn}."
                ALTERNATIVE="${DATABASE}_$(date +'%Y%m%d_%H%M')"
                    confirmYesNo "Do you wish restore ${DATABASE} to ${Cb}${ALTERNATIVE}${Cn}"
                [ "$confirmYesNo" == 'Y' ] && \
                    reanimate "${FILEDUMP}" "${DATABASE}" "${ALTERNATIVE}" && \
                    success
            ;;
        esac
        fail "${MESSAGE}"
    }

    # Ensure multilevel
    checkOptions "$@"
}

function manage {
    # Configure database tool.

    checkConfig

    function create {
        #manage: Configure a new database to be backuped.
        success message "Database tool configured."

        TARGET_FILE="${CONFIG_FILE}" && \
            confirmYesNo "Do you wish to store configs in your profile ${Cb}\`~/${CONFIG_FILE}\`${Cn}"
        [ "$confirmYesNo" == 'Y' ] && \
            TARGET_FILE="${HOME}/${CONFIG_FILE}"

        read -rp  'Hostname: ' HOSTNAME
        read -rp  'Database: ' DATABASE
        read -rp  'Username: ' USERNAME
        read -rsp 'Password: ' PASSWORD; $_e;    ALIAS="${DATABASE}"
        $_e -n "Choose an Alias/Label (suggestion: ${Cb}${DATABASE}${Cn}): "
        read -r ALIAS

        checkConfig "${ALIAS}" "${HOSTNAME}" "${DATABASE}" "${USERNAME}" "${PASSWORD}" && \
            confirmYesNo "Are you sure to save this config?"
        [ "$confirmYesNo" == 'Y' ] && \
            backup "${ALIAS} ${HOSTNAME} ${DATABASE} ${USERNAME} ${PASSWORD}" && \
            backup SAVE && \
            success
    }

    function list {
        #manage: Configure a new database to be backuped.
        success message "${Cb}${#DATABASES[@]}${Cn} databases configured."

        i=1
        for source in "${DATABASES[@]}"
        do
            # shellcheck disable=SC2086
            $_e "$i: $(checkConfig ${source})"
            i="$((i + 1))"
        done

        success
    }

    function remove {
        #manage: Remove database from procedure list.
        ALIAS="${DATABASES[$1]}"
        success message "Database ${Cb}$(checkConfig DATABASE "${ALIAS}")${Cn} removed from list."

        unset DATABASES[$1] && backup SAVE && success
    }

    # Ensure multilevel
    checkOptions "$@"
}

#
#       AVOID change above the safety line.
#
# -------------------------------------------------- SAFETY LINE -------------

APP_VERSION="${APP_MAJOR}.${APP_MINOR}.${APP_REVISION}-${APP_PATCH}"

function show_header {
    title="${Cb}${APP_TITLE}${Cn} v${APP_VERSION}"
    $_e "\n\n$title\n$(printf "%${#title}s" | tr ' ' '-')\n"
}

SHORT=

declare -a commands
commands=()

function help {
    # Show this content.
    success message "${EMPTY}"
    filter=' '

    [[ "$1"     != "" ]] && filter="$1: "
    [[ "$SHORT" == "" ]] && show_header && $_e "Usage: ${Cb}$0${Cn} $1 [${Cb}help${Cn}|..] ..

Parameters:
"
    scope=$filter

    function parse_help {
        content="$1"

        [ ! -e "$content" ] && content=$(which "$APP")
        [ ! -d "$content" ] || return 0

    $_e "content $content ;; filter $filter.." >> template.log

        list=$(grep 'function ' -A1 < "$content" | \
            awk -F-- '{print($1)}'  | \
            $_sed 's/fu''nction (.*) \{$/\1/' | \
            $_sed "s/.+#${filter}(.*)$/@ok\1/g" | \
            grep '@ok' -B1 | \
            $_sed 's/\@ok//' | \
            $_sed "s/^${scope}//" | tr '\n' '\ ' | $_sed 's/-- /\\n/g')

        OIFS="$IFS"
        IFS=$'\n' temporary=(${list//\\n/$'\n'})
        IFS="$OIFS"

        for command in "${temporary[@]}"
        do  commands[${#commands[@]}]="$command"
        done
    }

    function fill {
        size=${#1}
        str_repeat $((max_size - size)) ' '
    }

    function parseThis {
        [[ "$1" == "" ]] && return
        method="$1";shift
        $_e "${space}${Cb}${method}${Cn}$(fill "$method")${space}${*}"
    }

    parse_help


    if [ "$APP_RECIPES" != "NO" ] && [ "$APP_RECIPES" != "YES" ] && [[ -e "$APP_RECIPES" ]]
    then for recipe in "$APP_RECIPES"/*
        do parse_help "$recipe"
    $_e "\n\n\nparsing helps for $recipe" >> template.log
        done
    fi

    max_size=0
    space=$(fill four)

    for command in "${commands[@]}"
    do
    size=$(strlen "$($_e "$command" | awk '{print($1)}')")
    	[[ $size -gt $max_size ]] && max_size=$size
    done

    for line in "${commands[@]}"
    do
        # shellcheck disable=SC2086
        parseThis $line
    done

    success || fail 'Something terrible happens.'
}

#
# HELPERS
#
         confirmYesNo=
function confirmYesNo {
    d=N; N=n; Y=y
    if [ $# -gt 1 ]
    then case ${1^^} in
        -DY) Y=${Y^}; d=Y;;
        -DN) N=${N^}; d=N;;
        esac
        m=$2
    else
        m=$1
    fi
    eval "$d=\\${Cb}$d\\${Cn}"
    option="($Y/$N)? "
    $_e -n "$m ${option}"
    read -n 1 -r m; c=${m^}
    case $c in
        Y|N) n=$c;;
          *) n=$d;;
    esac
    $_e
    export confirmYesNo=$n;
}

#
# Hold a success message.
#
# Ex.:
#       success message "all commands executed"
#       command1
#       command2
#       command3 || fail "command 3 fail"
#       success
#
#  will execute command1, command2, command3 and print: "all commands executed"
#  when  success.
function success {
    if [ "$1"  == "message" ]
    then   success_message="$2"; return 0; fi
    $_e "${success_message}"
    $_e && success_message=
}

#
# Trigger a failure message with exit.
#
# Ex.:
#       success message "all commands executed"
#       command1
#       command2
#       command3 || fail "command 3 fail"
#       success
#
#  will execute command1, command2, command3 and print: "command 3 fail"
#  when command 3 fails.
function fail {
    $_e "\n$*\n" && exit 1
}

function strlen {
    $_e ${#1}
}

function str_repeat {
    printf '%*s' "$1" | tr ' ' "$2"
}

function functionExists {
    name="^${1} ()"
    $_e "searching for $name.." >> template.log
    typeset | grep "$name" >> template.log
    [[ $(typeset | grep "$name" | awk '{print($1)}') != '' ]] && $_e YES
}

#
#
function autocomplete {
    SHORT=on;Cn=;Cb=;Cd=;Ci=;Cr=;Cg=;Cy=;Cc=
    $_e "$(help "$1" | awk '{print($1)}')"
}

function config {
    # Configure application.

    function install {
        #config: Installs autocomplete features (need sudo).
        success message "Autocomplete instalado com sucesso.

        Reinicialize o terminal para que as mudanças façam efeito.

        Você pode utilizar o comando \`${Cb}reset${Cn}\` para realizar esse processo."

        function _autocomplete_Template {
            local curr prev

            curr="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"
            APP='%APP%'

            [[ "${prev}" ==   "$APP" ]] && prev=;
            [[ "${prev}" == "./$APP" ]] && prev=;

            options=$($APP autocomplete ${prev})
            COMPREPLY=( $(compgen -W "${options}" -- "${curr}"))
            return 0
        }

        clean=$($_e "$APP" | $_sed 's/([a-z0-9A-Z]*).*$/\1/')
        target="/etc/bash_completion.d/$APP"

        cp "$APP" "/bin/$APP"
        chmod +x  "/bin/$APP"
        $_e "$(declare -f _autocomplete_Template)\n\n"  | \
            sed -e "s/%APP%/${APP}/" | \
            sed -e "s/_Template/${clean}/"  > "$target"

        for each in ".\/${APP}" "${APP}"
        do [[ $UID -eq 0 ]] &&  $_e "Configuring autocomplete.." && \
            $_e "complete -F _autocomplete_Template %APP%" | \
                sed -e "s/%APP%/${each}/" | \
                sed -e "s/_Template/${clean}/" >> "$target" && \
                src "$target" && \
                success
        done
    }

    checkOptions "$@"
}

function checkOptions {
    [[ "$APP_RECIPES" != "NO" ]] && search_for_recipes
    if [ ${#} -eq 0 ]
    then help "$__$*"
    else [ "$(functionExists "$1")" != "YES" ] \
            && help \
            && fail "Warning: ${Cb}$1${Cn} is an invalid command."
        [[ "${__}" == "" ]] && __="$1"
        "$@"
    fi
}

#
# DECORATION
COLORS=$(tput colors 2> /dev/null)
# shellcheck disable=SC2181
if [ $? = 0 ] && [ "${COLORS}" -gt 2 ]; then
    # shellcheck disable=SC2034
    C="\033"
    Cn="$C[0m"  # normal/reset
    Cb="$C[1m"  # bold
    # shellcheck disable=SC2034
    Cd="$C[2m"  # dark/gray
    # shellcheck disable=SC2034
    Ci="$C[3m"  # italic
    # shellcheck disable=SC2034
    Cr="$C[31m" # red
    # shellcheck disable=SC2034
    Cg="$C[32m" # green
    # shellcheck disable=SC2034
    Cy="$C[33m" # yellow
    # shellcheck disable=SC2034
    Cc="$C[34m" # blue
fi

function search_for_recipes {
    RCP="$(pwd)/.$($_e "/$APP" | $_sed 's/.*\/(.*)$/\1/')"
    for recipes in "$RCP"/*
    do  if  [ -e "$recipes" ]
        then src "$recipes"
            APP_RECIPES="$RCP"
        fi
        cd "${APP_PATH}" || exit 1
        return
    done
    case "$1" in
        wow)  i=so;;
        so)   i=many;;
        many) i=levels;;
        levels)
            cd "${APP_PATH}" || exit 1
            APP_RECIPES=NO
            return
            ;;
        *) i=wow;;
    esac
    cd ..
    search_for_recipes "$i"
}

function src {

    [ ! -e "$1" ] && return

    # shellcheck disable=SC1090
    source "$1"
}

#
# ALIAS TO COMMON RESOURCES
    max_size=
    _sed='sed -E'
    _e='echo -e'
    __=

#
# FUNCTION CALLER
checkOptions "$@"
