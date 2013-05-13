# base aliases
alias reload!='. ~/.zshrc'
alias less='less -R' # -R preserves ANSI color escape sequences in output
alias ls='ls --color -l'
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
