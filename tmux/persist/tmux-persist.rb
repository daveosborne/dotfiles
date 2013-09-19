#!/usr/bin/env ruby
%x[rm ~/.dotfiles/tmux/persist/*-restore.zsh]

sessions = %x[tmux list-sessions -F "\#{session_name}"].split("\n")

sessions.each do |session_name|

  pane_output = %x[tmux list-panes -t #{session_name} -s -F "\#{window_index} \#{pane_index} \#{window_width} \#{window_height} \#{pane_width} \#{pane_height} \#{window_name} \#{pane_current_path} \#{pane_pid}"].split("\n")

  panes = []
  pane_output.each do |pane_line|
    temp_pane = pane_line.split(" ")
    panes.push({
      window_index: Integer(temp_pane[0]),
      pane_index: Integer(temp_pane[1]),
      window_width: Integer(temp_pane[2]),
      window_height: Integer(temp_pane[3]),
      pane_width: Integer(temp_pane[4]),
      pane_height: Integer(temp_pane[5]),
      window_name: temp_pane[6],
      cwd: temp_pane[7],
      pid: temp_pane[8]
    })
  end

  windows_sh = ""
  panes.each do |pane|
    pane[:cmd] = %x[ps --no-headers -o cmd --ppid #{pane[:pid]}].delete("\n")
    pane[:cmd] = %x[ps --no-headers -o cmd #{pane[:pid]}].delete("\n").gsub(/^-/,"") unless pane[:cmd] != ""

    windows_sh += "tmux new-window -t $SESSION -a -n #{pane[:window_name]} \"cd #{pane[:cwd]} && #{pane[:cmd]}\"\n"

    if pane[:pane_index] > 0
      if pane[:pane_width] < pane[:window_width]
        windows_sh += "tmux join-pane -h -l #{pane[:pane_width]} -s $SESSION:#{pane[:window_index] +1}.0 -t $SESSION:#{pane[:window_index]}\n"
      else
        windows_sh += "tmux join-pane -v -l #{pane[:pane_height]} -s $SESSION:#{pane[:window_index] +1}.0 -t $SESSION:#{pane[:window_index]}\n"
      end
    end
  end

  File.open("/home/dosborne/.dotfiles/tmux/persist/#{session_name}-restore.zsh","w") {|f| f.write(<<EOF
#!/usr/bin/env bash
SESSION=#{session_name}

if [ -z $TMUX ]; then

  # if session already exists, attach
  tmux has-session -t $SESSION 
  if [ $? -eq 0 ]; then
    echo \"Session $SESSION already exists. Attaching...\"
    tmux attach -t $SESSION
    exit 0;
  fi

  # make new session
  tmux new-session -d -s $SESSION

#{windows_sh}

  # attach to new session
  tmux select-window -t $SESSION:1
  tmux attach-session -t $SESSION

fi
EOF
)}

end

