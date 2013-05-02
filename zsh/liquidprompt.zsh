
################################################################################
# LIQUID PROMPT
# An intelligent and non intrusive prompt for bash and zsh
################################################################################


# Licensed under the AGPL version 3
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

###########
# AUTHORS #
###########

# Alex Prengère     <alexprengere@gmail.com>      # untracked git files
# Aurelien Requiem  <aurelien@requiem.fr>         # Major clean refactoring, variable path length, error codes, several bugfixes.
# Clément Mathieu   <clement@unportant.info>      # Bazaar support
# David Loureiro    <david.loureiro@sysfera.com>  # small portability fix
# Étienne Deparis   <etienne.deparis@umaneti.net> # Fossil support
# Florian Le Frioux <florian@lefrioux.fr>         # Use ± mark when root in VCS dir.
# François Schmidts <francois.schmidts@gmail.com> # small code fix, _lp_get_dirtrim
# Frédéric Lepied   <flepied@gmail.com>           # Python virtual env
# Jonas Bengtsson   <jonas.b@gmail.com>           # Git remotes fix
# Joris Dedieu      <joris@pontiac3.nfrance.com>  # Portability framework, FreeBSD support, bugfixes.
# Joris Vaillant    <joris.vaillant@gmail.com>    # small git fix
# Luc Didry         <luc@fiat-tux.fr>             # Zsh port, several fix
# Ludovic Rousseau  <ludovic.rousseau@gmail.com>  # Lot of bugfixes.
# Nicolas Lacourte  <nicolas@dotinfra.fr>         # screen title
# nojhan            <nojhan@gmail.com>            # Main author.
# Olivier Mengué    <dolmen@cpan.org>             # Major optimizations on host parsing
# Poil              <poil@quake.fr>               # speed improvements
# Thomas Debesse    <thomas.debesse@gmail.com>    # Fix columns use.
# Yann 'Ze' Richard <ze@nbox.org>                 # Do not fail on missing commands.

# See the README.md file for a summary of features.

# Check for recent enough version of bash.
if test -n "$BASH_VERSION" -a -n "$PS1" -a -n "$TERM" ; then
    bash=${BASH_VERSION%.*}; bmajor=${bash%.*}; bminor=${bash#*.}
    if [[ $bmajor -lt 3 ]] || [[ $bmajor -eq 3 && $bminor -lt 2 ]]; then
        unset bash bmajor bminor
        return
    fi
    unset bash bmajor bminor

    _LP_WORKING_SHELL=bash
    _LP_OPEN_ESC="\["
    _LP_CLOSE_ESC="\]"
    _LP_USER_SYMBOL="\u"
    _LP_HOST_SYMBOL="\h"
    _LP_TIME_SYMBOL="\\\\t"
elif test -n "$ZSH_VERSION" ; then
    _LP_WORKING_SHELL=zsh
    _LP_OPEN_ESC="%{"
    _LP_CLOSE_ESC="%}"
    _LP_USER_SYMBOL="%n"
    _LP_HOST_SYMBOL="%m"
    _LP_TIME_SYMBOL="%*"
else
    echo "liquidprompt: shell not supported" >&2
    return
fi


###############
# OS specific #
###############

# LP_OS detection, default to Linux
case $(uname) in
    FreeBSD)   LP_OS=FreeBSD ;;
    DragonFly) LP_OS=FreeBSD ;;
    Darwin)    LP_OS=Darwin  ;;
    SunOS)     LP_OS=SunOS   ;;
    *)         LP_OS=Linux   ;;
esac

# Get cpu count
case "$LP_OS" in
    Linux)   _lp_CPUNUM=$( nproc 2>/dev/null || grep -c '^[Pp]rocessor' /proc/cpuinfo ) ;;
    FreeBSD|Darwin) _lp_CPUNUM=$( sysctl -n hw.ncpu ) ;;
    SunOS)   _lp_CPUNUM=$( kstat -m cpu_info | grep -c "module: cpu_info" ) ;;
esac


# get current load
case "$LP_OS" in
    Linux)
        _lp_cpu_load () {
            local load eol
            read load eol < /proc/loadavg
            echo "$load"
        }
        ;;
    FreeBSD)
        _lp_cpu_load () {
            local load
            load=$(LANG=C sysctl -n vm.loadavg | awk '{print $2}')
            echo "$load"
        }
        ;;
    Darwin)
        _lp_cpu_load () {
            local load
            load=$(LANG=C sysctl -n vm.loadavg | awk '{print $2}')
            echo "$load"
        }
        LP_DWIN_KERNEL_REL_VER=$(uname -r | cut -d . -f 1)
        ;;
    SunOS)
        _lp_cpu_load () {
            LANG=C uptime | awk '{print substr($10,0,length($10))}'
        }
esac


#################
# CONFIGURATION #
#################

# The following code is run just once. But it is encapsulated in a function
# to benefit of 'local' variables.
#
# What we do here:
# 1. Setup variables that can be used by the user: the "API" of liquidprompt
#    for config/theme. Those variables are local to the function.
#    In practice, this is only color variables.
# 2. Setup default values
# 3. Load the configuration
_lp_source_config()
{

    # TermInfo feature detection
    local ti_sgr0="$( { tput sgr0 || tput me ; } 2>/dev/null )"
    local ti_bold="$( { tput bold || tput md ; } 2>/dev/null )"
    local ti_setaf
    if tput setaf >/dev/null 2>&1 ; then
        ti_setaf () { tput setaf "$1" ; }
    elif tput AF >/dev/null 2>&1 ; then
        # *BSD
        ti_setaf () { tput AF "$1" ; }
    else
        echo "liquidprompt: terminal $TERM not supported" >&2
        ti_setaf () { : ; }
    fi

    # Colors: variables are local so they will have a value only
    # during config loading and will not conflict with other values
    # with the same names defined by the user outside the config.
    local BOLD="${_LP_OPEN_ESC}${ti_bold}${_LP_CLOSE_ESC}"

    local BLACK="${_LP_OPEN_ESC}$(ti_setaf 0)${_LP_CLOSE_ESC}"
    local BOLD_GRAY="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 0)${_LP_CLOSE_ESC}"
    local WHITE="${_LP_OPEN_ESC}$(ti_setaf 7)${_LP_CLOSE_ESC}"
    local BOLD_WHITE="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 7)${_LP_CLOSE_ESC}"

    local RED="${_LP_OPEN_ESC}$(ti_setaf 1)${_LP_CLOSE_ESC}"
    local BOLD_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 1)${_LP_CLOSE_ESC}"
    local WARN_RED="${_LP_OPEN_ESC}$(ti_setaf 0 ; tput setab 1)${_LP_CLOSE_ESC}"
    local CRIT_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 7 ; tput setab 1)${_LP_CLOSE_ESC}"
    local DANGER_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 3 ; tput setab 1)${_LP_CLOSE_ESC}"

    local GREEN="${_LP_OPEN_ESC}$(ti_setaf 2)${_LP_CLOSE_ESC}"
    local BOLD_GREEN="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 2)${_LP_CLOSE_ESC}"

    local YELLOW="${_LP_OPEN_ESC}$(ti_setaf 3)${_LP_CLOSE_ESC}"
    local BOLD_YELLOW="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 3)${_LP_CLOSE_ESC}"

    local BLUE="${_LP_OPEN_ESC}$(ti_setaf 4)${_LP_CLOSE_ESC}"
    local BOLD_BLUE="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 4)${_LP_CLOSE_ESC}"

    local PURPLE="${_LP_OPEN_ESC}$(ti_setaf 5)${_LP_CLOSE_ESC}"
    local PINK="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 5)${_LP_CLOSE_ESC}"

    local CYAN="${_LP_OPEN_ESC}$(ti_setaf 6)${_LP_CLOSE_ESC}"
    local BOLD_CYAN="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 6)${_LP_CLOSE_ESC}"

    # NO_COL is special: it will be used at runtime, not just during config loading
    NO_COL="${_LP_OPEN_ESC}${ti_sgr0}${_LP_CLOSE_ESC}"

    unset ti_sgr0 ti_bold ti_setaf


    # Default values (globals)
    LP_BATTERY_THRESHOLD=${LP_BATTERY_THRESHOLD:-75}
    LP_LOAD_THRESHOLD=${LP_LOAD_THRESHOLD:-60}
    LP_PATH_LENGTH=${LP_PATH_LENGTH:-35}
    LP_PATH_KEEP=${LP_PATH_KEEP:-2}
    LP_HOSTNAME_ALWAYS=${LP_HOSTNAME_ALWAYS:-0}
    LP_USER_ALWAYS=${LP_USER_ALWAYS:-1}
    LP_PERCENTS_ALWAYS=${LP_PERCENTS_ALWAYS:-1}
    LP_PS1=${LP_PS1:-""}
    LP_PS1_PREFIX=${LP_PS1_PREFIX:-""}
    LP_TITLE_OPEN=${LP_TITLE_OPEN:-"\e]0;"}
    LP_TITLE_CLOSE=${LP_TITLE_CLOSE:-"\a"}
    LP_SCREEN_TITLE_OPEN=${LP_SCREEN_TITLE_OPEN:-"\033k"}
    LP_SCREEN_TITLE_CLOSE=${LP_SCREEN_TITLE_CLOSE:-"\033\134"}

    LP_ENABLE_PERM=${LP_ENABLE_PERM:-1}
    LP_ENABLE_SHORTEN_PATH=${LP_ENABLE_SHORTEN_PATH:-1}
    LP_ENABLE_PROXY=${LP_ENABLE_PROXY:-1}
    LP_ENABLE_JOBS=${LP_ENABLE_JOBS:-1}
    LP_ENABLE_LOAD=${LP_ENABLE_LOAD:-1}
    LP_ENABLE_BATT=${LP_ENABLE_BATT:-1}
    LP_ENABLE_GIT=${LP_ENABLE_GIT:-1}
    LP_ENABLE_SVN=${LP_ENABLE_SVN:-1}
    LP_ENABLE_FOSSIL=${LP_ENABLE_FOSSIL:-1}
    LP_ENABLE_HG=${LP_ENABLE_HG:-1}
    LP_ENABLE_BZR=${LP_ENABLE_BZR:-1}
    LP_ENABLE_TIME=${LP_ENABLE_TIME:-0}
    LP_ENABLE_VIRTUALENV=${LP_ENABLE_VIRTUALENV:-1}
    LP_ENABLE_VCS_ROOT=${LP_ENABLE_VCS_ROOT:-0}
    LP_ENABLE_TITLE=${LP_ENABLE_TITLE:-0}
    LP_ENABLE_SCREEN_TITLE=${LP_ENABLE_SCREEN_TITLE:-0}
    LP_ENABLE_SSH_COLORS=${LP_ENABLE_SSH_COLORS:-0}
    LP_DISABLED_VCS_PATH=${LP_DISABLED_VCS_PATH:-""}

    LP_MARK_DEFAULT=${LP_MARK_DEFAULT:-""}
    LP_MARK_BATTERY=${LP_MARK_BATTERY:-"⌁"}
    LP_MARK_ADAPTER=${LP_MARK_ADAPTER:-"⏚"}
    LP_MARK_LOAD=${LP_MARK_LOAD:-"⌂"}
    LP_MARK_PROXY=${LP_MARK_PROXY:-"↥"}
    LP_MARK_HG=${LP_MARK_HG:-"☿"}
    LP_MARK_SVN=${LP_MARK_SVN:-"‡"}
    LP_MARK_GIT=${LP_MARK_GIT:-"±"}
    LP_MARK_FOSSIL=${LP_MARK_FOSSIL:-"⌘"}
    LP_MARK_BZR=${LP_MARK_BZR:-"⚯"}
    LP_MARK_UNTRACKED=${LP_MARK_UNTRACKED:-"*"}
    LP_MARK_STASH=${LP_MARK_STASH:-"+"}
    LP_MARK_BRACKET_OPEN=${LP_MARK_BRACKET_OPEN:-"["}
    LP_MARK_BRACKET_CLOSE=${LP_MARK_BRACKET_CLOSE:-"]"}
    LP_MARK_SHORTEN_PATH=${LP_MARK_SHORTEN_PATH:-" … "}

    LP_COLOR_PATH=${LP_COLOR_PATH:-$BOLD_WHITE}
    LP_COLOR_PATH_ROOT=${LP_COLOR_PATH_ROOT:-$BOLD_YELLOW}
    LP_COLOR_PROXY=${LP_COLOR_PROXY:-$BOLD_BLUE}
    LP_COLOR_JOB_D=${LP_COLOR_JOB_D:-$YELLOW}
    LP_COLOR_JOB_R=${LP_COLOR_JOB_R:-$BOLD_YELLOW}
    LP_COLOR_JOB_Z=${LP_COLOR_JOB_Z:-$BOLD_YELLOW}
    LP_COLOR_ERR=${LP_COLOR_ERR:-$PURPLE}
    LP_COLOR_MARK=${LP_COLOR_MARK:-$BOLD_WHITE}
    LP_COLOR_MARK_ROOT=${LP_COLOR_MARK_ROOT:-$BOLD_RED}
    LP_COLOR_USER_LOGGED=${LP_COLOR_USER_LOGGED:-""}
    LP_COLOR_USER_ALT=${LP_COLOR_USER_ALT:-$BOLD}
    LP_COLOR_USER_ROOT=${_ROOT:-$BOLD_YELLOW}
    LP_COLOR_HOST=${LP_COLOR_HOST:-""}
    LP_COLOR_SSH=${LP_COLOR_SSH:-$BLUE}
    LP_COLOR_SU=${LP_COLOR_SU:-$BOLD_YELLOW}
    LP_COLOR_TELNET=${LP_COLOR_TELNET:-$WARN_RED}
    LP_COLOR_X11_ON=${LP_COLOR_X11:-$GREEN}
    LP_COLOR_X11_OFF=${LP_COLOR_X11:-$YELLOW}
    LP_COLOR_WRITE=${LP_COLOR_WRITE:-$GREEN}
    LP_COLOR_NOWRITE=${LP_COLOR_NOWRITE:-$RED}
    LP_COLOR_UP=${LP_COLOR_UP:-$GREEN}
    LP_COLOR_COMMITS=${LP_COLOR_COMMITS:-$YELLOW}
    LP_COLOR_CHANGES=${LP_COLOR_CHANGES:-$RED}
    LP_COLOR_DIFF=${LP_COLOR_DIFF:-$PURPLE}
    LP_COLOR_CHARGING_ABOVE=${LP_COLOR_CHARGING_ABOVE:-$GREEN}
    LP_COLOR_CHARGING_UNDER=${LP_COLOR_CHARGING_UNDER:-$YELLOW}
    LP_COLOR_DISCHARGING_ABOVE=${LP_COLOR_DISCHARGING_ABOVE:-$YELLOW}
    LP_COLOR_DISCHARGING_UNDER=${LP_COLOR_DISCHARGING_UNDER:-$RED}
    LP_COLOR_TIME=${LP_COLOR_TIME:-$BLUE}
    LP_COLOR_IN_MULTIPLEXER=${LP_COLOR_IN_MULTIPLEXER:-$BOLD_BLUE}

    LP_COLORMAP_0=${LP_COLORMAP_0:-""}
    LP_COLORMAP_1=${LP_COLORMAP_1:-$GREEN}
    LP_COLORMAP_2=${LP_COLORMAP_2:-$BOLD_GREEN}
    LP_COLORMAP_3=${LP_COLORMAP_3:-$YELLOW}
    LP_COLORMAP_4=${LP_COLORMAP_4:-$BOLD_YELLOW}
    LP_COLORMAP_5=${LP_COLORMAP_5:-$RED}
    LP_COLORMAP_6=${LP_COLORMAP_6:-$BOLD_RED}
    LP_COLORMAP_7=${LP_COLORMAP_7:-$WARN_RED}
    LP_COLORMAP_8=${LP_COLORMAP_8:-$CRIT_RED}
    LP_COLORMAP_9=${LP_COLORMAP_9:-$DANGER_RED}


    # Default config file may be the XDG standard ~/.config/liquidpromptrc,
    # but heirloom dotfile has priority.

    local configfile
    if [[ -f "/etc/liquidpromptrc" ]]
    then
        source "/etc/liquidpromptrc"
    fi
    if [[ -f "$HOME/.liquidpromptrc" ]]
    then
        configfile="$HOME/.liquidpromptrc"
    elif [[ -z "$XDG_HOME_DIR" ]]
    then
        configfile="$HOME/.config/liquidpromptrc"
    else
        configfile="$XDG_HOME_DIR/liquidpromptrc"
    fi
    if [[ -f "$configfile" ]]
    then
        source "$configfile"
    fi
}
# do source config files
_lp_source_config
unset _lp_source_config

# Disable features if the tool is not installed
[[ "$LP_ENABLE_GIT"  = 1 ]] && { command -v git  >/dev/null || LP_ENABLE_GIT=0  ; }
[[ "$LP_ENABLE_SVN"  = 1 ]] && { command -v svn  >/dev/null || LP_ENABLE_SVN=0  ; }
[[ "$LP_ENABLE_FOSSIL"  = 1 ]] && { command -v fossil  >/dev/null || LP_ENABLE_FOSSIL=0  ; }
[[ "$LP_ENABLE_HG"   = 1 ]] && { command -v hg   >/dev/null || LP_ENABLE_HG=0   ; }
[[ "$LP_ENABLE_BZR"  = 1 ]] && { command -v bzr > /dev/null || LP_ENABLE_BZR=0  ; }
[[ "$LP_ENABLE_BATT" = 1 ]] && { command -v acpi >/dev/null || LP_ENABLE_BATT=0 ; }

# Escape the given strings
# Must be used for all strings that may comes from remote sources,
# like VCS branch names
_lp_escape()
{
    printf "%q" "$*"
}


###############
# Who are we? #
###############

# Yellow for root, bold if the user is not the login one, else no color.
if [[ "$EUID" -ne "0" ]] ; then  # if user is not root
    # if user is not login user
    if [[ ${USER} != "$(logname 2>/dev/null)" ]]; then
        LP_USER="${LP_COLOR_USER_ALT}${_LP_USER_SYMBOL}${NO_COL}"
    else
        if [[ "${LP_USER_ALWAYS}" -ne "0" ]] ; then
            LP_USER="${LP_COLOR_USER_LOGGED}${_LP_USER_SYMBOL}${NO_COL}"
        else
            LP_USER=""
        fi
    fi
else
    LP_USER="${LP_COLOR_USER_ROOT}${_LP_USER_SYMBOL}${NO_COL}"
fi


#################
# Where are we? #
#################

_lp_connection()
{
    if [[ -n "$SSH_CLIENT$SSH2_CLIENT$SSH_TTY" ]] ; then
        echo ssh
    else
        # TODO check on *BSD
        local sess_src=$(who am i | sed -n 's/.*(\(.*\))/\1/p')
        local sess_parent=$(ps -o comm= -p $PPID)
        if [[ -z "$sess_src" || "$sess_src" = ":"* ]] ; then
            echo lcl  # Local
        elif [[ "$sess_parent" = "su" || "$sess_parent" = "sudo" ]] ; then
            echo su   # Remote su/sudo
        else
            echo tel  # Telnet
        fi
    fi
}

# Put the hostname if not locally connected
# color it in cyan within SSH, and a warning red if within telnet
# else diplay the host without color
# The connection is not expected to change from inside the shell, so we
# build this just once
LP_HOST=""
_chroot()
{
    if [[ -r /etc/debian_chroot ]] ; then
        local debchroot
        debchroot=$(cat /etc/debian_chroot)
        echo "(${debchroot})"
    fi
}
LP_HOST="$(_chroot)"
unset _chroot

# If we are connected with a X11 support
if [[ -n "$DISPLAY" ]] ; then
    LP_HOST="${LP_COLOR_X11_ON}${LP_HOST}@${NO_COL}"
else
    LP_HOST="${LP_COLOR_X11_OFF}${LP_HOST}@${NO_COL}"
fi

case "$(_lp_connection)" in
lcl)
    if [[ "${LP_HOSTNAME_ALWAYS}" -eq "0" ]] ; then
        # FIXME do we want to display the chroot if local?
        LP_HOST="" # no hostname if local
    else
        LP_HOST="${LP_HOST}${LP_COLOR_HOST}${_LP_HOST_SYMBOL}${NO_COL}"
    fi
    ;;
ssh)
    # If we want a different color for each host
    if [[ "$LP_ENABLE_SSH_COLORS" -eq "1" ]]; then
        # compute the hash of the hostname
        # and get the corresponding number in [1-6] (red,green,yellow,blue,purple or cyan)
        # FIXME check portability of cksum and add more formats (bold? 256 colors?)
        hash=$(( 1 + $(hostname | cksum | cut -d " " -f 1) % 6 ))
        color=${_LP_OPEN_ESC}$(ti_setaf $hash)${_LP_CLOSE_ESC}
        LP_HOST="${LP_HOST}${color}${_LP_HOST_SYMBOL}${NO_COL}"
        unset hash
        unset color
    else
        # the same color for all hosts
        LP_HOST="${LP_HOST}${LP_COLOR_SSH}${_LP_HOST_SYMBOL}${NO_COL}"
    fi
    ;;
su)
    LP_HOST="${LP_HOST}${LP_COLOR_SU}${_LP_HOST_SYMBOL}${NO_COL}"
    ;;
tel)
    LP_HOST="${LP_HOST}${LP_COLOR_TELNET}${_LP_HOST_SYMBOL}${NO_COL}"
    ;;
*)
    LP_HOST="${LP_HOST}${_LP_HOST_SYMBOL}" # defaults to no color
    ;;
esac

# Useless now, so undefine
# unset _lp_connection


# put an arrow if an http proxy is set
_lp_proxy()
{
    [[ "$LP_ENABLE_PROXY" != 1 ]] && return

    if [[ ! -z "$http_proxy" ]] ; then
        echo -ne "$LP_COLOR_PROXY$LP_MARK_PROXY$NO_COL"
    fi
}

# BASH/ZSH function that shortens
# a very long path for display by removing
# the left most parts and replacing them
# with a leading ...
#
# the first argument is the path
#
# the second argument is the maximum allowed
# length including the '/'s and ...
# http://hbfs.wordpress.com/2009/09/01/short-pwd-in-bash-prompts/
#
# + keep some left part of the path if asked
_lp_shorten_path()
{
    if [[ "$LP_ENABLE_SHORTEN_PATH" != 1 || -n "$PROMPT_DIRTRIM" ]] ; then
        if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
            echo "\\w"
        else
            echo "$(print -P "%~")"
        fi
        return
    fi
    # the character that will replace the part of the path that is masked
    local mask="$LP_MARK_SHORTEN_PATH"
    # index of the directory to keep from the root (starts at 0 whith bash, 1 with zsh)
    local keep=$((LP_PATH_KEEP-1))
    if [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
       keep=$LP_PATH_KEEP
    fi

    local p="${PWD/$HOME/~}"
    local len="${#p}"

    local max_len=$((${COLUMNS:-80}*$LP_PATH_LENGTH/100))
    local mask_len="${#mask}"
    local slashes=0

    if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
        if [[ "$len" -gt "$max_len" ]]
        then
            # finds all the '/' in
            # the path and stores their
            # positions
            #
            local pos=()
            for ((i=0;i<len;i++))
            do
                if [[ "${p:i:1}" == "/" ]]
                then
                    pos=(${pos[@]} $i)
                    slashes=$((${slashes}+1))
                fi
            done
            pos=(${pos[@]} $len)

            # we have the '/'s, let's find the
            # left-most that doesn't break the
            # length limit
            #
            local i=$keep
            if [[ $keep > $slashes ]] ; then
                i=$slashes
            fi
            while [[ "$((len-pos[i]))" -gt "$((max_len-mask_len))" ]]
            do
                i=$((i+1))
            done

            # let us check if it's OK to
            # print the whole thing
            #
            if [[ "${pos[i]}" -eq "0" ]]
            then
                # the path is shorter than
                # the maximum allowed length,
                # so no need for ...
                #
                echo "$p"

            elif [[ "${pos[i]}" = "$len" ]]
            then
                # constraints are broken because
                # the maximum allowed size is smaller
                # than the last part of the path, plus
                # ' … '
                #
                echo "${p:0:((${pos[${keep}]}+1))}${mask}${p:((len-max_len+mask_len))}"
            else
                # constraints are satisfied, at least
                # some parts of the path, plus ' … ', are
                # shorter than the maximum allowed size
                #
                echo "${p:0:((${pos[${keep}]}+1))}${mask}${p:pos[i]}"
            fi
        else
            echo "$p"
        fi
    elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
        if [[ "$len" -gt "$max_len" ]]; then
            echo "%-${keep}~%${max_len}<${mask}<%~%<<"
        else
            echo "%~"
        fi
    fi
}

# In bash shell, PROMPT_DIRTRIM is the number of directory to keep at the end
# of the displayed path (if "\w" is present in the PS1 var).
# liquidprompt can calculate this number under two condition, path shortening
# must be activated and PROMPT_DIRTRIM must be already set.
_lp_get_dirtrim() {
    [[ "$LP_ENABLE_SHORTEN_PATH" != 1 ]] && echo 0 && return

    local p="${PWD/$HOME/~}"
    local len=${#p}
    local max_len=$((${COLUMNS:-80}*$LP_PATH_LENGTH/100))
    local PROMPT_DIRTRIM=0

    if [[ "$((len))" -gt "$((max_len))" ]]; then
        local i

        for ((i=$len;i>=0;i--))
        do
            [[ $(($len-$i)) -gt $max_len ]] && break
            [[ "${p:i:1}" == "/" ]] && PROMPT_DIRTRIM=$((PROMPT_DIRTRIM+1))
        done
        [[ "$((PROMPT_DIRTRIM))" -eq 0 ]] && PROMPT_DIRTRIM=1
    fi
    echo "$PROMPT_DIRTRIM"
}

# Display a ":"
# colored in green if user have write permission on the current directory
# colored in red if it have not.
_lp_permissions_color()
{
    if [[ "$LP_ENABLE_PERM" != 1 ]]; then
        echo : # without color
    else
        if [[ -w "${PWD}" ]]; then
            echo "${LP_COLOR_WRITE}:${NO_COL}"
        else
            echo "${LP_COLOR_NOWRITE}:${NO_COL}"
        fi
    fi
}

# Display the current Python virtual environnement, if available.
_lp_virtualenv()
{
    [[ "$LP_ENABLE_VIRTUALENV" != 1 ]] && return
    [[ -n "$VIRTUAL_ENV" ]] && echo "[$(basename $VIRTUAL_ENV)]"
}


################
# Related jobs #
################

# Display the count of each if non-zero:
# - detached screens sessions and/or tmux sessions running on the host
# - attached running jobs (started with $ myjob &)
# - attached stopped jobs (suspended with Ctrl-Z)
_lp_jobcount_color()
{
    [[ "$LP_ENABLE_JOBS" != 1 ]] && return

    local running=$(( $(jobs -r | wc -l) ))
    local stopped=$(( $(jobs -s | wc -l) ))
    local n_screen=$(screen -ls 2> /dev/null | grep -c Detach)
    local n_tmux=$(tmux list-sessions 2> /dev/null | grep -cv attached)
    local detached=$(( $n_screen + $n_tmux ))
    local m_detached="d"
    local m_stop="z"
    local m_run="&"
    local ret=""

    if [[ $detached != "0" ]] ; then
        ret="${ret}${LP_COLOR_JOB_D}${detached}${m_detached}${NO_COL}"
    fi

    if [[ $running != "0" ]] ; then
        if [[ $ret != "" ]] ; then ret="${ret}/"; fi
        ret="${ret}${LP_COLOR_JOB_R}${running}${m_run}${NO_COL}"
    fi

    if [[ $stopped != "0" ]] ; then
        if [[ $ret != "" ]] ; then ret="${ret}/"; fi
        ret="${ret}${LP_COLOR_JOB_Z}${stopped}${m_stop}${NO_COL}"
    fi

    echo -ne "$ret"
}


# Tells if we are running in a terminal multiplexer
_lp_in_multiplexer()
{
    if [[ "$TERM" == screen* ]] ; then
        echo -ne "in_multiplexer"
    fi
}


# Display the return value of the last command, if different from zero
_lp_return_value()
{
    if [[ "$1" -ne "0" ]]
    then
        echo -ne "$LP_COLOR_ERR$1$NO_COL"
    fi
}


######################
# VCS branch display #
######################

_lp_are_vcs_disabled()
{
    [[ -z "$LP_DISABLED_VCS_PATH" ]] && echo 0 && return
    local path
    local IFS=:
    for path in $LP_DISABLED_VCS_PATH; do
        if [[ "$PWD" == *"$path"* ]]; then
            echo 1
            return
        fi
    done
    echo 0
}

# GIT #

# Get the branch name of the current directory
_lp_git_branch()
{
    [[ "$LP_ENABLE_GIT" != 1 ]] && return
    local gitdir
    gitdir="$(git rev-parse --git-dir 2>/dev/null)"
    [[ $? -ne 0 || ! $gitdir =~ (.*\/)?\.git.* ]] && return
    local branch="$(git symbolic-ref HEAD 2>/dev/null)"
    if [[ $? -ne 0 || -z "$branch" ]] ; then
        # In detached head state, use commit instead
        branch="$(git rev-parse --short HEAD 2>/dev/null)"
    fi
    [[ $? -ne 0 || -z "$branch" ]] && return
    branch="${branch#refs/heads/}"
    echo $(_lp_escape "$branch")
}

# Set a color depending on the branch state:
# - green if the repository is up to date
# - yellow if there is some commits not pushed
# - red if there is changes to commit
#
# Add the number of pending commits and the impacted lines.
_lp_git_branch_color()
{
    [[ "$LP_ENABLE_GIT" != 1 ]] && return

    local branch
    branch=$(_lp_git_branch)
    if [[ ! -z "$branch" ]] ; then

        local GD
        git diff --quiet >/dev/null 2>&1
        GD=$?

        local GDC
        git diff --cached --quiet >/dev/null 2>&1
        GDC=$?

        local has_untracked
        has_untracked=$(git status 2>/dev/null | grep '\(# Untracked\)')
        if [[ -z "$has_untracked" ]] ; then
            has_untracked=""
        else
            has_untracked="$LP_COLOR_CHANGES$LP_MARK_UNTRACKED"
        fi

        local has_stash
        has_stash=$(git stash list 2>/dev/null)
        if [[ -z "$has_stash" ]] ; then
            has_stash=""
        else
            has_stash="$LP_COLOR_COMMITS$LP_MARK_STASH"
        fi

        local remote
        remote="$(git config --get branch.${branch}.remote 2>/dev/null)"
        # if git has no upstream, use origin
        if [[ -z "$remote" ]]; then
            remote="origin"
        fi
        local remote_branch
        remote_branch="$(git config --get branch.${branch}.merge 2>/dev/null)"
        # without any remote branch, use the same name
        if [[ -z "$remote_branch" ]]; then
            remote_branch="$branch"
        fi

        local has_commit
        has_commit=0
        if [[ -n "$remote" && -n "$remote_branch" ]] ; then
            has_commit=$(git rev-list --no-merges --count $remote/${remote_branch}..${branch} 2>/dev/null)
            if [[ -z "$has_commit" ]] ; then
                has_commit=0
            fi
        fi
        if [[ "$GD" -eq 1 || "$GDC" -eq "1" ]] ; then
            local has_line
            has_lines=$(git diff --numstat 2>/dev/null | awk 'NF==3 {plus+=$1; minus+=$2} END {printf("+%d/-%d\n", plus, minus)}')
            if [[ "$has_commit" -gt "0" ]] ; then
                # Changes to commit and commits to push
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL},${LP_COLOR_COMMITS}$has_commit${NO_COL})${has_stash}${has_untracked}${NO_COL}"
            else
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL})${has_stash}${has_untracked}${NO_COL}" # changes to commit
            fi
        else
            if [[ "$has_commit" -gt "0" ]] ; then
                # some commit(s) to push
                ret="${LP_COLOR_COMMITS}${branch}${NO_COL}(${LP_COLOR_COMMITS}$has_commit${NO_COL})${has_stash}${has_untracked}${NO_COL}"
            else
                ret="${LP_COLOR_UP}${branch}${has_stash}${has_untracked}${NO_COL}" # nothing to commit or push
            fi
        fi
        echo -ne "$ret"
    fi
}


# MERCURIAL #

# Get the branch name of the current directory
_lp_hg_branch()
{
    [[ "$LP_ENABLE_HG" != 1 ]] && return
    local branch
    branch="$(hg branch 2>/dev/null)"
    [[ $? -eq 0 ]] && echo $(_lp_escape "$branch")

}

# Set a color depending on the branch state:
# - green if the repository is up to date
# - red if there is changes to commit
# - TODO: yellow if there is some commits not pushed
_lp_hg_branch_color()
{
    [[ "$LP_ENABLE_HG" != 1 ]] && return

    local branch
    local ret
    branch=$(_lp_hg_branch)
    if [[ ! -z "$branch" ]] ; then

        local has_untracked
        has_untracked=$(hg status 2>/dev/null | grep '\(^\?\)' | wc -l)
        if [[ -z "$has_untracked" ]] ; then
            has_untracked=""
        else
            has_untracked="$LP_COLOR_CHANGES$LP_MARK_UNTRACKED"
        fi

        local has_commit
        has_commit=$(hg outgoing --no-merges ${branch} 2>/dev/null | grep '\(^changeset\:\)' | wc -l)
        if [[ -z "$has_commit" ]] ; then
            has_commit=0
        fi

        if [[ $(( $(hg status --quiet -n | wc -l) )) = 0 ]] ; then
            if [[ "$has_commit" -gt "0" ]] ; then
                # some commit(s) to push
                ret="${LP_COLOR_COMMITS}${branch}${NO_COL}(${LP_COLOR_COMMITS}$has_commit${NO_COL})${has_untracked}${NO_COL}"
            else
                ret="${LP_COLOR_UP}${branch}${has_untracked}${NO_COL}" # nothing to commit or push
            fi
        else
            local has_line
            has_lines=$(hg diff --stat 2>/dev/null | tail -n 1 | awk 'FS=" " {printf("+%s/-%s\n", $4, $6)}')
            if [[ "$has_commit" -gt "0" ]] ; then
                # Changes to commit and commits to push
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL},${LP_COLOR_COMMITS}$has_commit${NO_COL})${has_untracked}${NO_COL}"
            else
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL})${has_untracked}${NO_COL}" # changes to commit
            fi
        fi
        echo -ne "$ret"
    fi
}

# SUBVERSION #

# Get the branch name of the current directory
# For the first level of the repository, gives the repository name
_lp_svn_branch()
{
    [[ "$LP_ENABLE_SVN" != 1 ]] && return
    local root
    local url
    local result
    eval $(LANG=C LC_ALL=C svn info 2>/dev/null | sed -n 's/^URL: \(.*\)/url="\1"/p;s/^Repository Root: \(.*\)/root="\1"/p' )
    if [[ "$root" == "" ]]; then
        return
    fi
    # Make url relative to root
    url="${url:${#root}}"
    if [[ "$url" == */trunk* ]] ; then
        echo -n trunk
    else
        result=$(expr "$url" : '.*/branches/\([^/]*\)' || expr "$url" : '/\([^/]*\)' || basename "$root")
        echo -n $result # FIXME should be: echo -n $(_lp_escape "${result}")
    fi
}

# Set a color depending on the branch state:
# - green if the repository is clean
#   (use $LP_SVN_STATUS_OPTS to define what that means with
#    the --depth option of 'svn status')
# - red if there is changes to commit
# Note that, due to subversion way of managing changes,
# informations are only displayed for the CURRENT directory.
_lp_svn_branch_color()
{
    [[ "$LP_ENABLE_SVN" != 1 ]] && return

    local branch
    branch="$(_lp_svn_branch)"
    if [[ -n "$branch" ]] ; then
        local commits
        changes=$(( $(svn status $LP_SVN_STATUS_OPTIONS | grep -c -v "?") ))
        if [[ $changes -eq 0 ]] ; then
            echo "${LP_COLOR_UP}${branch}${NO_COL}"
        else
            echo "${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$changes${NO_COL})" # changes to commit
        fi
    fi
}


# FOSSIL #

# Get the tag name of the current directory
_lp_fossil_branch()
{
    [[ "$LP_ENABLE_FOSSIL" != 1 ]] && return
    local branch
    branch=$(fossil status 2>/dev/null | grep tags: | cut -c17-)
    if [[ -n "$branch" ]] ; then
        echo $(_lp_escape "$branch")
    else
        if fossil info &>/dev/null ; then
            echo "no-tag"
        fi
    fi
}

# Set a color depending on the branch state:
# - green if the repository is clean
# - red if there is changes to commit
# - yellow if the branch has no tag name
#
# Add the number of impacted files with a
# + when files are ADDED or EDITED
# - when files are DELETED
_lp_fossil_branch_color()
{
    [[ "$LP_ENABLE_FOSSIL" != 1 ]] && return

    local branch
    branch=$(_lp_fossil_branch)

    if [[ ! -z "$branch" ]] ; then
        local C2E # Modified files (added or edited)
        local C2D # Deleted files
        local C2A # Extras files
        local ret
        C2E=$(fossil changes | wc -l)
        C2D=$(fossil changes | grep DELETED | wc -l)
        let "C2E = $C2E - $C2D"
        C2A=$(fossil extras | wc -l)
        ret=""

        if [[ "$C2E" -gt 0 ]] ; then
            ret+="+$C2E"
        fi

        if [[ "$C2D" -gt 0 ]] ; then
            if [[ "$ret" = "" ]] ; then
                ret+="-$C2D"
            else
                ret+="/-$C2D"
            fi
        fi

        if [[ "$C2A" -gt 0 ]] ; then
            C2A="$LP_MARK_UNTRACKED"
        else
            C2A=""
        fi

        if [[ "$ret" != "" ]] ; then
            ret="(${LP_COLOR_DIFF}$ret${NO_COL})"
        fi


        if [[ "$branch" = "no-tag" ]] ; then
            # Warning, your branch has no tag name !
            branch="${LP_COLOR_COMMITS}$branch${NO_COL}$ret${LP_COLOR_COMMITS}$C2A${NO_COL}"
        else
            if [[ "$C2E" -eq 0 && "$C2D" -eq 0 ]] ; then
                # All is up-to-date
                branch="${LP_COLOR_UP}$branch$C2A${NO_COL}"
            else
                # There're some changes to commit
                branch="${LP_COLOR_CHANGES}$branch${NO_COL}$ret${LP_COLOR_CHANGES}$C2A${NO_COL}"
            fi
        fi
        echo -ne $branch # $(_lp_escape "$branch")
    fi
}

# Bazaar #

# Get the branch name of the current directory
_lp_bzr_branch()
{
    [[ "$LP_ENABLE_BZR" != 1 ]] && return
    local branch
    branch=$(bzr nick 2> /dev/null)
    [[ $? -ne 0 ]] && return
    echo $(_lp_escape "$branch")
}


# Set a color depending on the branch state:
# - green if the repository is up to date
# - red if there is changes to commit
# - TODO: yellow if there is some commits not pushed
#
# Add the number of pending commits and the impacted lines.
_lp_bzr_branch_color()
{
    [[ "$LP_ENABLE_BZR" != 1 ]] && return
    local output
    output=$(bzr version-info --check-clean --custom --template='{branch_nick} {revno} {clean}' 2> /dev/null)
    local tuple=($output)
    local branch=${tuple[0]}
    local revno=${tuple[1]}
    local clean=${tuple[2]}

    if [[ ! -z "$branch" ]] ; then
        if [[ "$clean" -eq 0 ]] ; then
            ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_COMMITS}$revno${NO_COL})"
        else
            ret="${LP_COLOR_UP}${branch}${NO_COL}(${LP_COLOR_COMMITS}$revno${NO_COL})"
        fi

    fi
    echo -ne "$ret"
}


##################
# Battery status #
##################

# Get the battery status in percent
# returns 0 (and battery level) if battery is discharging and under threshold
# returns 1 (and battery level) if battery is discharging and above threshold
# returns 2 (and battery level) if battery is charging but under threshold
# returns 3 (and battery level) if battery is charging and above threshold
# returns 4 if no battery support
_lp_battery()
{
    [[ "$LP_ENABLE_BATT" != 1 ]] && return
    local acpi
    acpi="$(acpi --battery 2>/dev/null)"
    # Extract the battery load value in percent
    # First, remove the beginning of the line...
    local bat="${acpi#Battery *, }"
    bat="${bat%%%*}" # remove everything starting at '%'

    if [[ -z "${bat}" ]] ; then
        # not battery level found
        return 4

    # discharging
    elif [[ "$acpi" == *"Discharging"* ]] ; then
        if [[ ${bat} -le $LP_BATTERY_THRESHOLD ]] ; then
            # under threshold
            echo -n "${bat}"
            return 0
        else
            # above threshold
            echo -n "${bat}"
            return 1
        fi

    # charging
    else
        if [[ ${bat} -le $LP_BATTERY_THRESHOLD ]] ; then
            # under threshold
            echo -n "${bat}"
            return 2
        else
            # above threshold
            echo -n "${bat}"
            return 3
        fi
    fi
}

# Compute a gradient of background/foreground colors depending on the battery status
# Display:
# a  green ⏚ if the battery is charging    and above threshold
# a yellow ⏚ if the battery is charging    and under threshold
# a yellow ⌁ if the battery is discharging but above threshold
# a    red ⌁ if the battery is discharging and above threshold
_lp_battery_color()
{
    [[ "$LP_ENABLE_BATT" != 1 ]] && return

    local mark=$LP_MARK_BATTERY
    local chargingmark=$LP_MARK_ADAPTER
    local bat
    local ret
    bat=$(_lp_battery)
    ret=$?

    if [[ $ret == 4 || $bat == 100 ]] ; then
        # no battery support or battery full: nothing displayed
        return
    elif [[ $ret == 3 && $bat != 100 ]] ; then
        # charging and above threshold and not 100%
        # green ⏚
        echo -ne "${LP_COLOR_CHARGING_ABOVE}$chargingmark${NO_COL}"
        return
    elif [[ $ret == 2 ]] ; then
        # charging but under threshold
        # yellow ⏚
        echo -ne "${LP_COLOR_CHARGING_UNDER}$chargingmark${NO_COL}"
        return
    elif [[ $ret == 1 ]] ; then
        # discharging but above threshold
        # yellow ⌁
        echo -ne "${LP_COLOR_DISCHARGING_ABOVE}$mark${NO_COL}"
        return

    # discharging and under threshold
    elif [[ "$bat" != "" ]] ; then
        ret="${LP_COLOR_DISCHARGING_UNDER}${mark}${NO_COL}"

        if [[ "$LP_PERCENTS_ALWAYS" -eq "1" ]]; then
            if   [[ ${bat} -le 100 ]] && [[ ${bat} -gt 80 ]] ; then # -20
                ret="${ret}${LP_COLORMAP_1}"
            elif [[ ${bat} -le 80  ]] && [[ ${bat} -gt 65 ]] ; then # -15
                ret="${ret}${LP_COLORMAP_2}"
            elif [[ ${bat} -le 65  ]] && [[ ${bat} -gt 50 ]] ; then # -15
                ret="${ret}${LP_COLORMAP_3}"
            elif [[ ${bat} -le 50  ]] && [[ ${bat} -gt 40 ]] ; then # -10
                ret="${ret}${LP_COLORMAP_4}"
            elif [[ ${bat} -le 40  ]] && [[ ${bat} -gt 30 ]] ; then # …
                ret="${ret}${LP_COLORMAP_5}"
            elif [[ ${bat} -le 30  ]] && [[ ${bat} -gt 20 ]] ; then
                ret="${ret}${LP_COLORMAP_6}"
            elif [[ ${bat} -le 20  ]] && [[ ${bat} -gt 10 ]] ; then
                ret="${ret}${LP_COLORMAP_7}"
            elif [[ ${bat} -le 10  ]] && [[ ${bat} -gt 5  ]] ; then
                ret="${ret}${LP_COLORMAP_8}"
            elif [[ ${bat} -le 5   ]] && [[ ${bat} -gt 0  ]] ; then
                ret="${ret}${LP_COLORMAP_9}"
            else
                # for debugging purpose
                ret="${ret}${LP_COLORMAP_0}"
            fi

            if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
                ret="${ret}${bat}%"
            elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
                ret="${ret}${bat}%%"
            fi
        fi # LP_PERCENTS_ALWAYS
        echo -ne "${ret}${NO_COL}"
    fi # ret
}


###############
# System load #
###############

# Compute a gradient of background/forground colors depending on the battery status
_lp_load_color()
{
    # Colour progression is important ...
    #   bold gray -> bold green -> bold yellow -> bold red ->
    #   black on red -> bold white on red
    #
    # Then we have to choose the values at which the colours switch, with
    # anything past yellow being pretty important.

    [[ "$LP_ENABLE_LOAD" != 1 ]] && return

    local load
    local IFS=" \t\n"
    load="$(_lp_cpu_load | sed 's/\.//g;s/^0*//g' )"
    let "load=${load:-0}/$_lp_CPUNUM"

    if [[ $load -ge $LP_LOAD_THRESHOLD ]]
    then
        local ret
        ret=""
        if   [[ $load -ge 0   ]] && [[ $load -lt 20  ]] ; then
            ret="${ret}${LP_COLORMAP_0}"
        elif [[ $load -ge 20  ]] && [[ $load -lt 40  ]] ; then
            ret="${ret}${LP_COLORMAP_1}"
        elif [[ $load -ge 40  ]] && [[ $load -lt 60  ]] ; then
            ret="${ret}${LP_COLORMAP_2}"
        elif [[ $load -ge 60  ]] && [[ $load -lt 80  ]] ; then
            ret="${ret}${LP_COLORMAP_3}"
        elif [[ $load -ge 80  ]] && [[ $load -lt 100 ]] ; then
            ret="${ret}${LP_COLORMAP_4}"
        elif [[ $load -ge 100 ]] && [[ $load -lt 120 ]] ; then
            ret="${ret}${LP_COLORMAP_5}"
        elif [[ $load -ge 120 ]] && [[ $load -lt 140 ]] ; then
            ret="${ret}${LP_COLORMAP_6}"
        elif [[ $load -ge 140 ]] && [[ $load -lt 160 ]] ; then
            ret="${ret}${LP_COLORMAP_7}"
        elif [[ $load -ge 160 ]] && [[ $load -lt 180 ]] ; then
            ret="${ret}${LP_COLORMAP_8}"
        elif [[ $load -ge 180 ]] ; then
            ret="${ret}${LP_COLORMAP_9}"
        else
            ret="${ret}${LP_COLORMAP_0}"
        fi
        ret="$ret${LP_MARK_LOAD}"

        if [[ "$LP_PERCENTS_ALWAYS" -eq "1" ]]; then
            if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
                ret="${ret}$load%"
            elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
                ret="${ret}$load%%"
            fi
        fi
        echo -ne "${ret}${NO_COL}"
    fi
}


##########
# DESIGN #
##########

# Remove all colors and escape characters of the given string and return a pure text
_lp_as_text()
{
    # Remove colors from the computed prompt
    local pst=$(echo $1 | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")

    # Remove escape sequences
    # FIXME check the zsh compatibility
    # pst=$(echo $pst | sed "s,\\\\\\[\|\\\\\\],,g")
    local op=$(printf "%q" "$_LP_OPEN_ESC")
    local cl=$(printf "%q" "$_LP_CLOSE_ESC")
    pst=$(echo $pst | sed "s,$op\|$cl,,g") # replace all open _or_ close tags with nothing

    echo -n "$pst"
}

_lp_title()
{
    [[ "$LP_ENABLE_TITLE" != "1" ]] && return

    # Get the current computed prompt as pure text
    local txt=$(_lp_as_text "$1")

    # Use it in the window's title
    # Escapes whill tells bash to ignore the non-printing control characters when calculating the width of the prompt.
    # Otherwise line editing commands will mess the cursor positionning
    case "$TERM" in
      screen*)
        [[ "$LP_ENABLE_SCREEN_TITLE" != "1" ]] && return
        local title="${LP_SCREEN_TITLE_OPEN}${txt}${LP_SCREEN_TITLE_CLOSE}"
      ;;
      linux*)
        local title=""
      ;;
      *)
        local title="${_LP_OPEN_ESC}${LP_TITLE_OPEN}${txt}${LP_TITLE_CLOSE}${_LP_CLOSE_ESC}"
      ;;
    esac
    echo -n "${title}"
}

# Set the prompt mark to ± if git, to ☿ if mercurial, to ‡ if subversion
# to # if root and else $
_lp_smart_mark()
{
    local COL
    COL=${LP_COLOR_MARK}
    if [[ "$EUID" -eq "0" ]] ; then
        COL=${LP_COLOR_MARK_ROOT}
    fi

    local mark
    if [[ -n "$LP_MARK_DEFAULT" ]]; then
        mark=$LP_MARK_DEFAULT
    elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
        mark="%(!.#.%%)"
    else
        mark="\\\$"
    fi
    if [[ "$1" == "git" ]]; then
        mark=$LP_MARK_GIT
    elif [[ "$1" == "git-svn" ]]; then
        mark="$LP_MARK_GIT$LP_MARK_SVN"
    elif [[ "$1" == "hg" ]]; then
        mark=$LP_MARK_HG
    elif [[ "$1" == "svn" ]]; then
        mark=$LP_MARK_SVN
    elif [[ "$1" == "fossil" ]]; then
        mark=$LP_MARK_FOSSIL
    elif [[ "$1" == "bzr" ]]; then
        mark=$LP_MARK_BZR
    fi
    echo -ne "${COL}${mark}${NO_COL}"
}

# insert a space on the right
_lp_sr()
{
    if [[ ! -z "$1" ]] ; then
        echo -n "$1 "
    fi
}

# insert a space on the left
_lp_sl()
{
    if [[ ! -z "$1" ]] ; then
        echo -n " $1"
    fi
}

# insert two space, before and after
_lp_sb()
{
    if [[ ! -z "$1" ]] ; then
        echo -n " $1 "
    fi

}

###################
# CURRENT TIME    #
###################
_lp_time_analog()
{
    # get the date as "hours(12) minutes" in a single call
    # make a bash array with it
    d=( $(date "+%I %M") )
    # separate hours and minutes
    hour=${d[0]#0} # no leading 0
    min=${d[1]#0}

    # The targeted unicode characters are the "CLOCK FACE" ones
    # They are located in the codepages between:
    #     U+1F550 (ONE OCLOCK) and U+1F55B (TWELVE OCLOCK), for the plain hours
    #     U+1F55C (ONE-THIRTY) and U+1F567 (TWELVE-THIRTY), for the thirties
    #
    # Those codes may be output with unicode escapes or hexadecimal escapes,
    # the later being the more portable.
    #
    # But we can iterate only over integers.
    #
    # We thus need the following conversion table:
    #       utf   hex   int
    # hours 50:5B 90:9b 144:155
    # half  5C:67 9c:a7 156:167

    # The characters being grouped bas plain/thirty, we must first now
    # if we are close to the 0 or 30 minutes.
    # Bash using integer arithmetic by default, we do not need rounding.
    # We thus add 0 (plain hour) or 12 (half).
    # Then we add 144, which is the first index (as an integer).
    mi=$((144+12*($min/30)))

    # Add the computed minutes index (144 or 156) minus 1 (because the first hour starts at 0).
    hi=$(($mi+$hour-1))

    # Get the hexadecimal representation of this integer
    hex=$(printf "%x" $hi)

    # Print the first three bytes (that are always the same) and the computed last one.
    # Add a space for correct alignement
    echo -ne "\xf0\x9f\x95\x$hex "
}

_lp_time()
{
    [[ "$LP_ENABLE_TIME" != 1 ]] && return
    if [[ "$LP_TIME_ANALOG" != 1 ]]; then
        echo -ne "${LP_COLOR_TIME}${_LP_TIME_SYMBOL}${NO_COL}"
    else
        echo -ne "${LP_COLOR_TIME}$(_lp_time_analog)${NO_COL}"
    fi
}

########################
# Construct the prompt #
########################


_lp_set_prompt()
{
    # as this get the last returned code, it should be called first
    LP_ERR="$(_lp_sl $(_lp_return_value $?))"

    # execute the old prompt if not on Mac OS X (Mountain) Lion
    case "$LP_OS" in
        Linux|FreeBSD|SunOS) $LP_OLD_PROMPT_COMMAND ;;
        Darwin)
            case "$(LP_DWIN_KERNEL_REL_VER)" in
                11|12) update_terminal_cwd ;;
                *) $LP_OLD_PROMPT_COMMAND ;;
            esac ;;
    esac

    # left of main prompt: space at right
    LP_JOBS=$(_lp_sr "$(_lp_jobcount_color)")
    LP_LOAD=$(_lp_sr "$(_lp_load_color)")
    LP_BATT=$(_lp_sr "$(_lp_battery_color)")
    LP_TIME=$(_lp_sr "$(_lp_time)")

    # in main prompt: no space
    if [[ ! -z "$(_lp_in_multiplexer)" ]] ; then
        LP_MARK_BRACKET_OPEN="${LP_COLOR_IN_MULTIPLEXER}${LP_MARK_BRACKET_OPEN}${NO_COL}"
        LP_MARK_BRACKET_CLOSE="${LP_COLOR_IN_MULTIPLEXER}${LP_MARK_BRACKET_CLOSE}${NO_COL}"
    fi
    LP_PROXY="$(_lp_proxy)"

    # right of main prompt: space at left
    LP_VENV=$(_lp_sl "$(_lp_virtualenv)")
    LP_VCS=""
    if [[ "$LP_OLD_PWD" != "$PWD" ]]; then
        # LP_HOST is a global set at load time
        LP_PERM=$(_lp_permissions_color)
        LP_PWD=$(_lp_shorten_path)
        [[ -n "$PROMPT_DIRTRIM" ]] && PROMPT_DIRTRIM=$(_lp_get_dirtrim)

        if [[ "$(_lp_are_vcs_disabled)" -eq "0" ]] ; then
            LP_VCS="$(_lp_git_branch_color)"
            LP_VCS_TYPES="git"
            if [[ -n "$LP_VCS" ]]; then
                # If this is a git-svn repository
                if [[ -d "$(git rev-parse --git-dir 2>/dev/null)/svn" ]]; then
                    LP_VCS_TYPES="git-svn"
                fi
            fi # git-svn
            if [[ -z "$LP_VCS" ]]; then
                LP_VCS="$(_lp_hg_branch_color)"
                LP_VCS_TYPES="hg"
                if [[ -z "$LP_VCS" ]]; then
                    LP_VCS="$(_lp_svn_branch_color)"
                    LP_VCS_TYPES="svn"
                    if [[ -z "$LP_VCS" ]]; then
                        LP_VCS="$(_lp_fossil_branch_color)"
                        LP_VCS_TYPES="fossil"
                        if [[ -z "$LP_VCS" ]]; then
                            LP_VCS="$(_lp_bzr_branch_color)"
                            LP_VCS_TYPES="bzr"
                        fi # bzr
                    fi # fossil
                fi # svn
            fi # hg
        fi # disabled
        if [[ -z "$LP_VCS" ]] ; then
            LP_VCS_TYPES=""
        else
            LP_VCS=$(_lp_sl "${LP_VCS}")
        fi

        # end of the prompt line: double spaces
        LP_MARK=$(_lp_sb "$(_lp_smart_mark $LP_VCS_TYPES)")

        # Different path color if root
        if [[ "$EUID" -ne "0" ]] ; then
            LP_PWD="${LP_COLOR_PATH}${LP_PWD}${NO_COL}"
        else
            LP_PWD="${LP_COLOR_PATH_ROOT}${LP_PWD}${NO_COL}"
        fi
        LP_OLD_PWD="$PWD"

    elif [[ -n "$LP_VCS_TYPES" ]]; then
        case "$LP_VCS_TYPES" in
            git)    LP_VCS=$(_lp_sl "$(_lp_git_branch_color)");;
            git-svn)LP_VCS=$(_lp_sl "$(_lp_git_branch_color)");;
            hg)     LP_VCS=$(_lp_sl "$(_lp_hg_branch_color)");;
            svn)    LP_VCS=$(_lp_sl "$(_lp_svn_branch_color)");;
            fossil) LP_VCS=$(_lp_sl "$(_lp_fossil_branch_color)");;
            bzr)    LP_VCS=$(_lp_sl "$(_lp_bzr_branch_color)");;
        esac
    fi

    if [[ -f "$LP_PS1_FILE" ]]; then
        source "$LP_PS1_FILE"
    fi

    if [[ -z $LP_PS1 ]] ; then
        # add title escape time, jobs, load and battery
        PS1="${LP_PS1_PREFIX}${LP_TIME}${LP_BATT}${LP_LOAD}${LP_JOBS}"
        # add user, host and permissions colon
        PS1="${PS1}${LP_MARK_BRACKET_OPEN}${LP_USER}${LP_HOST}${LP_PERM}"

        # if not root
        if [[ "$EUID" -ne "0" ]]
        then
            # path in foreground color
            PS1="${PS1}${LP_PWD}${LP_MARK_BRACKET_CLOSE}${LP_VENV}${LP_PROXY}"
            # add VCS infos
            PS1="${PS1}${LP_VCS}"
        else
            # path in yellow
            PS1="${PS1}${LP_PWD}${LP_MARK_BRACKET_CLOSE}${LP_VENV}${LP_PROXY}"
            # do not add VCS infos unless told otherwise (LP_ENABLE_VCS_ROOT)
            [[ "$LP_ENABLE_VCS_ROOT" = "1" ]] && PS1="${PS1}${LP_VCS}"
        fi
        # add return code and prompt mark
        PS1="${PS1}${LP_ERR}${LP_MARK}"

        # "invisible" parts
        # Get the current prompt on the fly and make it a title
        LP_TITLE=$(_lp_title "$PS1")

        # Insert it in the prompt
        PS1="${LP_TITLE}${PS1}"

        # Glue the bash prompt always go to the first column.
        # Avoid glitches after interrupting a command with Ctrl-C
        # Does not seem to be necessary anymore?
        #PS1="\[\033[G\]${PS1}${NO_COL}"
    else
        PS1=$LP_PS1
    fi
}

prompt_tag()
{
    export LP_PS1_PREFIX=$(_lp_sr "$1")
}

# Activate the liquid prompt
prompt_on()
{
    # if liquidprompt has not been already set
    if [[ -z "$LP_LIQUIDPROMPT" ]] ; then
        LP_OLD_PS1="$PS1"
        if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
            LP_OLD_PROMPT_COMMAND="$PROMPT_COMMAND"
        elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
            LP_OLD_PROMPT_COMMAND="$precmd"
        fi
    fi
    if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
        PROMPT_COMMAND=_lp_set_prompt
    elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
        function precmd {
            _lp_set_prompt
        }
    fi

    # Keep in mind that LP has been sourced
    # (to avoid recursive prompt command).
    LP_LIQUIDPROMPT=1
}

# Come back to the old prompt
prompt_off()
{
    PS1=$LP_OLD_PS1
    if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
        PROMPT_COMMAND=$LP_OLD_PROMPT_COMMAND
    elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
        precmd=$LP_OLD_PROMPT_COMMAND
    fi
}

# Use an empty prompt: just the \$ mark
prompt_OFF()
{
    PS1="\$ "
    if [[ "$_LP_WORKING_SHELL" == "bash" ]]; then
        PROMPT_COMMAND=$LP_OLD_PROMPT_COMMAND
    elif [[ "$_LP_WORKING_SHELL" == "zsh" ]]; then
        precmd=$LP_OLD_PROMPT_COMMAND
    fi
}

# By default, sourcing liquidprompt.bash will activate the liquid prompt
prompt_on

# Cleaning of variable that are not needed at runtime
unset LP_OS

# vim: set et sts=4 sw=4 tw=120 ft=sh:
