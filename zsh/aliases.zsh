
case $(uname) in
    FreeBSD)   LP_OS=FreeBSD ;;
    DragonFly) LP_OS=FreeBSD ;;
    Darwin)    LP_OS=Darwin  ;;
    SunOS)     LP_OS=SunOS   ;;
    *)         LP_OS=Linux   ;;
esac

# base aliases
alias reload!='. ~/.zshrc'
alias less='less -R' # -R preserves ANSI color escape sequences in output
case $LP_OS in
  FreeBSD)    alias ls='ls -G -l'       ;;
  Linux)      alias ls='ls --color -l'  ;;
esac
alias l='ls'
alias grep='grep --color'
alias ff='find . -type f -name' # fast find
alias tmux='tmux -2'
alias peg='ps -ef |grep -i'
alias h1g='history 1 |grep -i'
alias df='df -h'
alias du='du -h'

# apt aliases
alias apti='sudo apt-get install'
alias apts='sudo apt-cache search'
alias aptp='sudo apt-cache policy'
alias aptu='sudo apt-get update && sudo apt-get upgrade'

# git aliases
alias gits='git status'
alias gitd='git diff'
alias gita='git add'
alias gitc='git commit'
alias grm='git rm'
alias push='git push origin'
alias pull='git pull'
alias branch='git checkout'
