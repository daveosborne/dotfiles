
SESSION=$USER

if [ -z $TMUX ]; then

  # if session already exists, attach
  tmux has-session -t $SESSION 
  if [ $? -eq 0 ]; then
    echo "Session $SESSION already exists. Attaching..."
    tmux attach -t $SESSION
    exit 0;
  fi

  # make new session
  tmux new-session -d -s $SESSION

  tmux set-window-option -t $SESSION -g automatic-rename off

  tmux new-window -t $SESSION -a -n work
  tmux new-window -t $SESSION -a -n vim 'cd ~/workspace;vim .'
  tmux new-window -t $SESSION -a -n syslog 'tail -f /var/log/syslog'
  tmux new-window -t $SESSION -a -n scratch

  # attach to new session
  tmux select-window -t $SESSION:1
  tmux attach-session -t $SESSION

fi
