# Enhanced User Setup Tool
# Original: https://github.com/georgeflanagin/usersetup
# Enhancements: 
#   - Explicit 'users' group addition
#   - User deletion functionality
#   - Time-limited guest accounts
#   - Improved sync_nodes.sh handling

# Get the default group from the remote machine.
export DEFAULT_GROUP=


function choosehost
{
    if [ -z "$1" ]; then
        cat<<EOF
Usage: choosehost {hostname}

This function sets the target computer for creating
users and installing keys. It sets the environment
variable USER_HOST.
EOF
        return
    fi

    case "$1" in
        localhost)
            export USER_HOST=$(hostname -s)
            ;;


        *)
            export USER_HOST="$1"
            ;;

    esac
    
    local scratchfile="/tmp/$USER_HOST.userdefaults.txt"


    ssh "root@$USER_HOST" "useradd -D" > "$scratchfile"
    DEFAULT_GROUP=$(cat "/tmp/$USER_HOST.userdefaults.txt" | grep "^GROUP=" | cut -d= -f2)
    if [ $? -ne 0 ] || [ -z "$DEFAULT_GROUP" ]; then
        echo "Cannot determine the default group on $USER_HOST"
        exit 1
    fi
    echo "Default group on $USER_HOST is $DEFAULT_GROUP"
    rm -f /tmp/$USER_HOST.userdefaults.txt
}


function userexists
{
    if [ -z "$1" ]; then
        echo "Usage: userexists <username>" >&2
        return 2
    fi

    local user="$1"

    if ! getent passwd "$user" > /dev/null; then
        echo "User '$user' does not exist"
        false
        return
    fi

    if grep -q "^$user:" /etc/passwd; then
        echo "User '$user' exists (local)"
    else
        echo "User '$user' exists (LDAP)"
    fi

    true
}

function groupexists
{
    if [[ $# -ne 1 ]]; then
        echo "Usage: groupexists <groupname>" >&2
        return 2
    fi

    if getent group "$1" > /dev/null; then
        if grep -q "^$1:" /etc/group; then
            echo "Group '$1' exists (local)"
        else
            echo "Group '$1' exists (remote, e.g. LDAP)"
        fi
        true

    else
        echo "Group '$1' does not exist"
        false
    fi
}

function adduserkey
{
    if [ -z "$1" ]; then
        cat<<EOF
    Usage: adduserkey {user} {keyfile}

    This will append the contents of keyfile to the
    .ssh/authorized_keys file of the user. It will
    create the user using the default profile if the
    user does not exist.
EOF
    fi

    if [ $(id -u) -ne 0 ]; then
        echo "addkey must be run as root."
        return
    fi

    user="$1"
    keyfile="$2"
    sshdir="/home/$user/.ssh"
    authkeys="$sshdir/authorized_keys"

    if ! userexists "$user"; then
        useradd -m "$user"
        echo "User $user added."
    else
        echo "User $user exists."
    fi

    if [ ! -d "/home/$user/.ssh" ]; then
        echo "Creating ssh directory."
        mkdir -p "$sshdir"
        chmod 700 "$sshdir"
        touch "$authkeys"
        chmod 600 "$authkeys"
        chown -R "$user" "$sshdir"
    fi

    if [ -e "$keyfile" ]; then
        cat "$keyfile" >> "$authkeys"
        echo "$keyfile appended to $authkeys"
    else
        echo "$keyfile not found"
    fi
}

function usersetup
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    if [ -z "$1" ]; then
        cat<<EOF
Usage: usersetup {netid} [keyfile] [expiry_days]
This will setup a user on $USER_HOST.

If you do not supply a keyfile, the function will
look in $PWD for a file that is named "netid.keys",
where netid is the netid of the user you want to
create and set up.

Optional expiry_days: Number of days until account expires (for guests).
Example: usersetup jsmith jsmith.keys 90
EOF
        return
    fi

    netid="$1"
    keyfile=${2-"$netid".keys}
    expiry_days="$3"

    ###
    # Explanation: if we find the user already has a known uid,
    #   then we use that id with the "-u uid" construct. If the
    #   value does not exist, we leave it out and let the system
    #   choose a unique id.
    ###
    uid=$(id -u $netid 2>/dev/null)
    if [ ! -z "$uid" ]; then
        uid="-u $uid"
    else
        uid=""
    fi

    ###
    cat<<EOF
Parameters:
    netid = "$netid"
    keyfile = "$keyfile"
    default_group = "$DEFAULT_GROUP"
    uid = "$uid"
    expiry_days = "${expiry_days:-none}"
EOF

    # If the user doesn't exist, then we create the user.
    echo "#!/bin/bash" > "$netid.sh"
    echo "# User setup script for $netid" >> "$netid.sh"
    echo "" >> "$netid.sh"
    
    echo "useradd -m $uid -s /bin/bash \"$netid\"" >> "$netid.sh"
    chmod 700 "$netid.sh"
    
    # Add to both DEFAULT_GROUP and 'users' group
    if [ ! -z "$DEFAULT_GROUP" ]; then
        echo "usermod -aG \"$DEFAULT_GROUP\" \"$netid\"" >> "$netid.sh"
    fi
    
    # ENHANCEMENT: Always add to 'users' group if it exists
    echo "if getent group users > /dev/null 2>&1; then" >> "$netid.sh"
    echo "    usermod -aG users \"$netid\"" >> "$netid.sh"
    echo "    echo \"Added $netid to 'users' group\"" >> "$netid.sh"
    echo "else" >> "$netid.sh"
    echo "    echo \"Warning: 'users' group does not exist on this system\"" >> "$netid.sh"
    echo "fi" >> "$netid.sh"
    echo "" >> "$netid.sh"
    
    if [ ! -z "$DEFAULT_GROUP" ]; then
        echo "chown \"$netid:$DEFAULT_GROUP\" \"/home/$netid\"" >> "$netid.sh"
        echo "chmod 2755 \"/home/$netid\"" >> "$netid.sh"
    fi

    # ENHANCEMENT: Set account expiration if specified
    if [ ! -z "$expiry_days" ]; then
        echo "# Set account expiration" >> "$netid.sh"
        echo "expiry_date=\$(date -d \"+${expiry_days} days\" +%Y-%m-%d)" >> "$netid.sh"
        echo "chage -E \"\$expiry_date\" \"$netid\"" >> "$netid.sh"
        echo "echo \"Account will expire on \$expiry_date\"" >> "$netid.sh"
    fi

    echo "" >> "$netid.sh"
    echo "mkdir -p \"/home/$netid/.ssh\"" >> "$netid.sh"
    echo "chmod 700 \"/home/$netid/.ssh\"" >> "$netid.sh"
    echo "" >> "$netid.sh"
    echo "touch \"/home/$netid/.ssh/authorized_keys\"" >> "$netid.sh"
    echo "chmod 600 \"/home/$netid/.ssh/authorized_keys\"" >> "$netid.sh"
    echo "chown -R \"$netid\" \"/home/$netid/.ssh\"" >> "$netid.sh"

    cat "$netid.sh"

    echo "Copying instructions to $USER_HOST"
    scp "$netid.sh" "root@$USER_HOST:~/."
    if [ $? -ne 0 ]; then
        echo "Failed to copy $netid.sh to $USER_HOST"
        return
    fi

    echo "Creating $netid on $USER_HOST"
    ssh "root@$USER_HOST" "bash ~/$netid.sh"
    if [ $? -ne 0 ]; then
        echo "Failed to create $netid on $USER_HOST"
        return
    fi


    # If there is a keyfile, then move it over and append it.
    if [ -e "$keyfile" ]; then
        echo "Copying $keyfile to $USER_HOST"
        scp "$keyfile" "root@$USER_HOST:~/."
        if [ $? -ne 0 ]; then
            echo "Unable to copy $keyfile to $USER_HOST"
            return
        fi
        ssh "root@$USER_HOST" "cat ~/$keyfile >> /home/$netid/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
            echo "Login key for $netid successfully installed on $USER_HOST"
            ssh "root@$USER_HOST" "chown $netid:$netid /home/$netid/.ssh/authorized_keys"
            ssh "root@$USER_HOST" "sudo -u $netid ssh-keygen -t ed25519 -N '' -f /home/$netid/.ssh/id_ed25519 -q"
            if [ $? -eq 0 ]; then
                echo "key for user $netid generated"
                ssh "root@$USER_HOST" "sudo -u $netid cat /home/$netid/.ssh/*.pub >> /home/$netid/.ssh/authorized_keys"
            else
                echo "key generation for $netid failed."
            fi
        else
            echo "Unable to attach key for $netid on $USER_HOST"
        fi
        
        # Clean up the keyfile on remote
        ssh "root@$USER_HOST" "rm -f ~/$keyfile"
    else
        echo "No key file. You will need to add this later."
    fi
    
    # Clean up the script on remote
    ssh "root@$USER_HOST" "rm -f ~/$netid.sh"

    # ENHANCEMENT: Improved sync_nodes.sh handling
    echo "Creating account for $netid on the nodes of $USER_HOST"
    
    # Copy sync scripts if they exist locally
    local sync_copied=false
    if [ -f "./sync_nodes.sh" ] && [ -f "./sync_all.sh" ]; then
        scp ./sync_nodes.sh ./sync_all.sh "root@$USER_HOST:~/" 2>/dev/null
        if [ $? -eq 0 ]; then
            ssh "root@$USER_HOST" "chmod +x ~/sync_nodes.sh ~/sync_all.sh" 2>/dev/null
            sync_copied=true
        fi
    elif [ -f ~/sync_nodes.sh ] && [ -f ~/sync_all.sh ]; then
        scp ~/sync_nodes.sh ~/sync_all.sh "root@$USER_HOST:~/" 2>/dev/null
        if [ $? -eq 0 ]; then
            ssh "root@$USER_HOST" "chmod +x ~/sync_nodes.sh ~/sync_all.sh" 2>/dev/null
            sync_copied=true
        fi
    fi
    
    # Run sync_nodes.sh if available
    ssh "root@$USER_HOST" "test -x ~/sync_nodes.sh" 2>/dev/null
    if [ $? -eq 0 ]; then
        ssh "root@$USER_HOST" "~/sync_nodes.sh" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Successfully synced user to compute nodes"
        else
            echo "Note: sync_nodes.sh execution failed"
        fi
    else
        if [ "$sync_copied" = true ]; then
            echo "Note: sync_nodes.sh not executable on $USER_HOST"
        else
            echo "Note: sync_nodes.sh not found, skipping node sync"
        fi
    fi
}

###
# NEW FUNCTION: Delete user from remote system
###
function userdelete
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    if [ -z "$1" ]; then
        cat<<EOF
Usage: userdelete {netid} [--force]

This will delete a user from $USER_HOST and all compute nodes.

WARNING: This will:
  - Kill all processes owned by the user
  - Remove the user's home directory
  - Remove the user from all groups
  - Delete the user account

Use --force to skip confirmation prompt.

Example: userdelete jsmith
         userdelete jsmith --force
EOF
        return
    fi

    netid="$1"
    force="$2"

    # Check if user exists on remote
    if ! ssh "root@$USER_HOST" "id $netid" > /dev/null 2>&1; then
        echo "User $netid does not exist on $USER_HOST"
        return 1
    fi

    # Confirmation unless --force is used
    if [ "$force" != "--force" ]; then
        echo "WARNING: You are about to delete user '$netid' from $USER_HOST"
        echo "This will remove:"
        echo "  - All processes owned by $netid"
        echo "  - Home directory: /home/$netid"
        echo "  - User account and group memberships"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "User deletion cancelled."
            return
        fi
    fi

    # Create deletion script
    cat > "$netid.delete.sh" <<'DELSCRIPT'
#!/bin/bash
USERNAME="$1"

echo "Deleting user: $USERNAME"

# Kill all processes owned by the user
echo "Killing processes owned by $USERNAME..."
pkill -u "$USERNAME" -TERM 2>/dev/null
sleep 2
pkill -u "$USERNAME" -KILL 2>/dev/null

# Check for any remaining processes
remaining=$(pgrep -u "$USERNAME" 2>/dev/null | wc -l)
if [ $remaining -gt 0 ]; then
    echo "Warning: $remaining processes still running for $USERNAME"
fi

# Remove cron jobs
echo "Removing cron jobs..."
crontab -r -u "$USERNAME" 2>/dev/null

# Backup home directory (optional - comment out if not needed)
if [ -d "/home/$USERNAME" ]; then
    backup_dir="/root/deleted_users"
    mkdir -p "$backup_dir"
    timestamp=$(date +%Y%m%d_%H%M%S)
    echo "Creating backup at $backup_dir/${USERNAME}_${timestamp}.tar.gz"
    tar -czf "$backup_dir/${USERNAME}_${timestamp}.tar.gz" "/home/$USERNAME" 2>/dev/null
fi

# Delete the user and home directory
echo "Deleting user account and home directory..."
userdel -r "$USERNAME" 2>&1

if [ $? -eq 0 ]; then
    echo "User $USERNAME successfully deleted"
    
    # Remove any lingering files
    find /var/spool/mail /var/mail -name "$USERNAME" -exec rm -f {} \; 2>/dev/null
    find /tmp -user "$USERNAME" -exec rm -rf {} \; 2>/dev/null
    
    # Remove from any additional group files
    sed -i "/^.*:.*:.*:.*$USERNAME.*/d" /etc/group 2>/dev/null
    
    echo "Cleanup complete"
else
    echo "Error: Failed to delete user $USERNAME"
    exit 1
fi
DELSCRIPT

    chmod 700 "$netid.delete.sh"

    echo "Copying deletion script to $USER_HOST"
    scp "$netid.delete.sh" "root@$USER_HOST:~/."
    if [ $? -ne 0 ]; then
        echo "Failed to copy deletion script to $USER_HOST"
        rm -f "$netid.delete.sh"
        return 1
    fi

    echo "Executing deletion on $USER_HOST"
    ssh "root@$USER_HOST" "bash ~/$netid.delete.sh $netid"
    if [ $? -eq 0 ]; then
        echo "User $netid deleted from $USER_HOST"
        
        # Sync to compute nodes
        echo "Syncing deletion to compute nodes..."
        ssh "root@$USER_HOST" "test -x ~/sync_nodes.sh" 2>/dev/null
        if [ $? -eq 0 ]; then
            ssh "root@$USER_HOST" "~/sync_nodes.sh" 2>/dev/null || echo "Note: sync_nodes.sh failed"
        else
            echo "Note: sync_nodes.sh not found, manual node sync may be needed"
        fi
        
        # Cleanup
        ssh "root@$USER_HOST" "rm -f ~/$netid.delete.sh"
        rm -f "$netid.delete.sh"
        
        echo "User deletion complete!"
    else
        echo "Failed to delete user $netid from $USER_HOST"
        rm -f "$netid.delete.sh"
        return 1
    fi
}

###
# NEW FUNCTION: List users and their expiration status
###
function listusers
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    cat<<EOF
Users on $USER_HOST:
=====================
EOF

    ssh "root@$USER_HOST" 'bash -s' <<'LISTSCRIPT'
#!/bin/bash
echo -e "Username\tUID\tGroups\t\t\tExpiration"
echo "--------------------------------------------------------------------------------"
while IFS=: read -r username _ uid _ _ home shell; do
    # Only show real users (UID >= 1000, exclude nobody)
    if [ $uid -ge 1000 ] && [ "$username" != "nobody" ]; then
        groups=$(groups "$username" 2>/dev/null | cut -d: -f2 | xargs)
        expiry=$(chage -l "$username" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
        if [ -z "$expiry" ]; then
            expiry="never"
        fi
        printf "%-16s%-8s%-32s%s\n" "$username" "$uid" "$groups" "$expiry"
    fi
done < /etc/passwd
LISTSCRIPT
}

###
# NEW FUNCTION: Extend or modify account expiration
###
function userexpiry
{
    if [ -z "$USER_HOST" ]; then
        echo "First .. setup the host using 'choosehost'"
        return
    fi

    if [ -z "$1" ] || [ -z "$2" ]; then
        cat<<EOF
Usage: userexpiry {netid} {days|never}

Modify account expiration for a user on $USER_HOST.

Examples:
  userexpiry jsmith 30      # Extend account 30 days from today
  userexpiry jsmith never   # Remove expiration (permanent account)
  userexpiry jsmith 0       # Expire account immediately
EOF
        return
    fi

    netid="$1"
    days="$2"

    if [ "$days" = "never" ]; then
        ssh "root@$USER_HOST" "chage -E -1 '$netid' 2>&1"
        if [ $? -eq 0 ]; then
            echo "Account expiration removed for $netid (account is now permanent)"
        else
            echo "Failed to modify expiration for $netid"
        fi
    else
        ssh "root@$USER_HOST" "chage -E \$(date -d '+${days} days' +%Y-%m-%d) '$netid' 2>&1"
        if [ $? -eq 0 ]; then
            expiry_date=$(ssh "root@$USER_HOST" "chage -l '$netid' | grep 'Account expires' | cut -d: -f2")
            echo "Account $netid will expire on: $expiry_date"
        else
            echo "Failed to set expiration for $netid"
        fi
    fi
}

###
# Help function
###
function usersetup_help
{
    cat<<EOF
User Setup Tool - Enhanced Version
===================================

Available functions:

  choosehost {hostname}
      Set the target host for user operations
      Example: choosehost server01

  usersetup {netid} [keyfile] [expiry_days]
      Create a new user account
      - Automatically adds to 'users' group
      - Optional: Set expiration for guest accounts
      Example: usersetup jsmith jsmith.keys
      Example: usersetup guest01 guest.keys 90

  userdelete {netid} [--force]
      Delete a user account (with backup)
      Example: userdelete jsmith
      Example: userdelete jsmith --force

  listusers
      Show all users and their expiration dates
      Example: listusers

  userexpiry {netid} {days|never}
      Modify account expiration
      Example: userexpiry jsmith 60
      Example: userexpiry jsmith never

  userexists {username}
      Check if a user exists

  groupexists {groupname}
      Check if a group exists

  adduserkey {user} {keyfile}
      Add SSH keys to existing user

Type the function name without arguments for detailed help.
EOF
}
