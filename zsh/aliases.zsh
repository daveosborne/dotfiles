
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
alias grep='grep --color'
alias ff='find . -type f -name' # fast find
alias tmux='tmux -2'

# apt aliases
alias apti='sudo apt-get install'
alias apts='sudo apt-cache search'
alias aptp='sudo apt-cache policy'

# git aliases
alias gits='git status'
alias gita='git add'
alias grm='git rm'
alias gitc='git commit'
alias push='git push origin'
alias pull='git pull'
alias branch='git checkout'
